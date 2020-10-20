pragma solidity ^0.6.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import './Interfaces/Compound/CErc20I.sol';
import './Interfaces/Compound/CTokenI.sol';
import './Interfaces/Compound/ComptrollerI.sol';

import './Interfaces/UniswapInterfaces/IUniswapV2Router02.sol';

import "./Interfaces/Yearn/IController.sol";

import "./Interfaces/DyDx/DydxFlashLoanBase.sol";
import "./Interfaces/DyDx/ICallee.sol";


//This strategies starting template is taken from https://github.com/iearn-finance/yearn-starter-pack/tree/master/contracts/strategies/StrategyDAICompoundBasic.sol
//Dydx code with help from money legos
contract YearnCompDaiStrategy is DydxFlashloanBase, ICallee {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant want = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address private constant SOLO = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;

    // Comptroller address for compound.finance
    ComptrollerI public constant compound = ComptrollerI(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B); 

    address public constant comp = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address public constant cDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // used for comp <> weth <> dai route
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 

    uint256 public performanceFee = 500;
    uint256 public constant performanceMax = 10000;

    uint256 public withdrawalFee = 50;
    uint256 public constant withdrawalMax = 10000;

    //multiple time 1000. so 4x target is 4000
    uint256 public leverageTarget = 3700;
    uint256 public minDAI = 100 * 1e18;
    uint256 public minCompToSell = 5 * 1e17; //0.5 comp
    bool public active = true;

    address public governance;
    address public controller;
    address public strategist;

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "LeveragedDaiCompStrat";
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }


    // This is the main deposit function for when people deposit into yearn strategy
    // If we already have a position we harvest it
    // then we calculate deficit of current position. and flash loan to get to desired position
    function deposit() public {
        

        //No point calling harvest if we dont own any cDAI. for instance on first deposit
        if(CErc20I(cDAI).balanceOf(address(this)) > 0)
        {
          
            _harvest();
        }

        //Want is DAI. 
        uint256 position; 
        bool deficit;
        uint256 _want;
        if(active){
            _want = IERC20(want).balanceOf(address(this));
            (position, deficit) = _calculateDesiredPosition(_want, true);
        }else{
            //if strategy is not active we want to deleverage as much as possible in one flash loan
            deficit = true;
            position = netBalanceLent();
        }
        

        //if we below minimun DAI change it is not worth doing        
        
        if (position > minDAI) {
           
            //flash loan to position 
            doFlashLoan(deficit, position);

        }
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(cDAI != address(_asset), "cDAI");
        require(comp != address(_asset), "comp");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
       require(msg.sender == controller, "!controller");

        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        
        CErc20I cd = CErc20I(cDAI);

       
       //this time we need real numbers and cant use cheaper stored values
        uint lent = cd.balanceOfUnderlying(address(this));
        uint borrowed = cd.borrowBalanceCurrent(address(this));
        
        _withdrawSome(lent.sub(borrowed));
        
        //now swap all remaining tokens for dai
        uint balance = cd.balanceOf(address(this));
        if(balance > 0){
            cd.redeem(balance);
        }

    }

    function harvest() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        //harvest and deposit public calls do the same thing
        deposit();    
       
    }

    //internal harvest. Public harvest calls deposit function
     function _harvest() internal {
         //claim comp accrued
        _claimComp();

        uint256 _comp = IERC20(comp).balanceOf(address(this));
        
        if (_comp > minCompToSell) {

            //for safety we set approval to 0 and then reset to required amount
            IERC20(comp).safeApprove(uni, 0);
            IERC20(comp).safeApprove(uni, _comp);

            address[] memory path = new address[](3);
            path[0] = comp;
            path[1] = weth;
            path[2] = want;

            (uint[] memory amounts) = IUniswapV2Router02(uni).swapExactTokensForTokens(_comp, uint256(0), path, address(this), now.add(1800));

            //amounts is array of the input token amount and all subsequent output token amounts
            uint256 _want = amounts[2];
            if (_want > 0) {
                uint256 _fee = _want.mul(performanceFee).div(performanceMax);
                IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
            }
        }
        
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {

        (uint256 position, bool deficit) = _calculateDesiredPosition(_amount, false);

        uint256 _before = IERC20(want).balanceOf(address(this));
        

        //flash loan to change position
        uint8 i = 0;
        //doflashloan should return should equal position unless there was not enough dai to flash loan
        while(position >0){

            require(i < 6, "too many iterations to withdraw");
            position = position.sub(doFlashLoan(deficit, position));

            i++;

        }

        //now withdraw
        //note - this can be optimised by calling in flash loan code
        CErc20I cd =CErc20I(cDAI);
        cd.redeemUnderlying(_amount);

        uint256 _after = IERC20(want).balanceOf(address(this));
        uint256 _withdrew = _after.sub(_before);
        return _withdrew;
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }


    function netBalanceLent() public view returns (uint256) {
         (uint deposits, uint borrows) =getCurrentPosition();
        return deposits.sub(borrows);
    }


    //a function to deleverage that does not rely on flash loans. it will take lots of calls but will eventually completely exit position
    //withdraw max possible. immediately repay debt
    function emergencyDeleverage() public {
        require(msg.sender == strategist || msg.sender == governance, "! strategist or governance");

        //minimun balance of lent is borrowed/ 0.75 
         CErc20I cd =CErc20I(cDAI);
         uint lent = cd.balanceOfUnderlying(address(this));

        //we can use storeed because interest was accrued in last line
         uint borrowed = cd.borrowBalanceStored(address(this));

         uint theoreticalLent = borrowed.mul(100).div(75);

         uint toRedeem = lent.sub(theoreticalLent);


        cd.redeemUnderlying(toRedeem);

        IERC20 _want = IERC20(want);
        uint balance = _want.balanceOf(address(this));
         _want.safeApprove(cDAI, 0);
         _want.safeApprove(cDAI, balance);

        cd.repayBorrow(balance);
        
    }

    function balanceC() public view returns (uint256) {
        return IERC20(cDAI).balanceOf(address(this));
    }

    //need to be redone
    function balanceOf() public view returns (uint256) {
       (uint deposits, uint borrows) =getCurrentPosition();
        return balanceOfWant().add(deposits).sub(borrows);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    //multiple time 1000. so 4x target is 4000
    function setCollateralTarget(uint256 target) external {
        require(msg.sender == strategist, "!strategist");
        require(target < 3990, "Target too close to 4x leverage");
        leverageTarget = target;
    }


    ///flash loan stuff

     function doFlashLoan(bool deficit, uint256 amount) internal returns (uint256){

    
        ISoloMargin solo = ISoloMargin(SOLO);

        uint256 marketId = _getMarketIdFromTokenAddress(SOLO, DAI);
        
       
      
        IERC20 token = IERC20(DAI);

        // Not enough DAI in DyDx. So we take all we can
        uint amountInSolo = token.balanceOf(SOLO);
        if(amountInSolo < amount)
        {
            amount = amountInSolo;
        }

        uint256 repayAmount = _getRepaymentAmountInternal(amount);

        token.safeApprove(SOLO, repayAmount);

        bytes memory data = abi.encode(deficit, amount);


        // 1. Withdraw $
        // 2. Call callFunction(...)
        // 3. Deposit back $
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

        operations[0] = _getWithdrawAction(marketId, amount);
        operations[1] = _getCallAction(
            // Encode custom data for callFunction
            data
        );
        operations[2] = _getDepositAction(marketId, repayAmount);

        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);

        return amount;
     }

    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public override {
        
        (bool deficit, uint256 amount) = abi.decode(data,(bool, uint256));
        IERC20 _want = IERC20(want);
        CErc20I cd =CErc20I(cDAI);

        
        //if in deficit we repay amount and then withdraw
        if(deficit){
           
            _want.safeApprove(cDAI, 0);
            _want.safeApprove(cDAI, amount);

            cd.repayBorrow(amount);


            //if we are withdrawing we take more
            cd.redeemUnderlying(_getRepaymentAmountInternal(amount));
        }else{
            uint amIn = _want.balanceOf(address(this));
            _want.safeApprove(cDAI, 0);
            _want.safeApprove(cDAI, amIn);

            cd.mint(amIn);

            cd.borrow(_getRepaymentAmountInternal(amount));

        }
    }


    function _claimComp() internal {
      
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] =  CTokenI(cDAI);

        compound.claimComp(address(this), tokens);
    }


    //This function works out what we want to change with our flash loan
    // Input balance is the amount we are going to deposit/withdraw. and dep is whether is this a deposit or withdrawal        
    function _calculateDesiredPosition(uint256 balance, bool dep) internal view returns (uint256 position, bool deficit){
        (uint256 deposits, uint256 borrows) = getCurrentPosition();


        //when we unwind we end up with the difference between borrow and supply
        uint unwoundDeposit = deposits.sub(borrows);

        //we want to see how close to collateral target we are. 
        //So we take deposits. Add or remove balance and see what desired lend is. then make difference

        uint desiredSupply = 0;
        if(dep){
            desiredSupply = unwoundDeposit.add(balance);
        }else{
            require(unwoundDeposit >= balance, "withdrawing more than balance");
            desiredSupply = unwoundDeposit.sub(balance);
        }

        //desired borrow is balance x leveraged targed-1. So if we want 4x leverage (max allowed). we want to borrow 3x desired balance
        uint desiredBorrow = desiredSupply.mul(leverageTarget.sub(1000)).div(1000);


        //now we see if we want to add or remove balance
        // if the desired borrow is less than our current borrow we are in deficit. so we want to reduce position
        if(desiredBorrow < borrows){
            deficit = true;
            position = borrows.sub(desiredBorrow);
        }else{
            //otherwise we want to increase position
             deficit = false;
            position = desiredBorrow.sub(borrows);
        }

    }

    //returns the current position
    //WARNING - this returns just the balance at last time someone touched the cDAI token. 
    //Does not accrue interest. 
    function getCurrentPosition() public view returns (uint deposits, uint borrows){
        CErc20I cd =CErc20I(cDAI);
       
        (, uint ctokenBalance, uint borrowBalance, uint exchangeRate) = cd.getAccountSnapshot(address(this));
        borrows = borrowBalance;

        //need to check this:
        deposits =  ctokenBalance.mul(exchangeRate).div(1e18);

    }

     function getLiquidity() public view returns (uint liquidity){
       ( , liquidity, ) = compound.getAccountLiquidity(address(this));

    }

    function disableLeverage() external {
        require(msg.sender == governance || msg.sender == strategist, "not governance or strategist");
        active = false;
    }
    function enableLeverage() external {
        require(msg.sender == governance || msg.sender == strategist, "not governance or strategist");
        active = true;
    }


    //calculate how many blocks until we are in liquidation based on current interest rates
     function getblocksUntilLiquidation() public view returns (uint256 blocks){
      (uint deposits, uint borrows) = getCurrentPosition();
        CErc20I cd =CErc20I(cDAI);
        uint borrrowRate = cd.borrowRatePerBlock();

        uint supplyRate = cd.supplyRatePerBlock();

        uint borrowAccural = borrrowRate.mul(borrows);
        uint supplyAccrual = supplyRate.mul(deposits);

        //we will never be ion lquidation
        if(borrowAccural <= supplyAccrual ){
            blocks = uint256(-1);
        }else{
            uint accrual = borrowAccural.sub(supplyAccrual).div(1e18);

            //we are in liquidation when borrows = 75% of deposits
            uint amountToGo = (deposits.mul(75).div(100)).sub(borrows);
         
            blocks = amountToGo.div(accrual);

            //we need to go back to last time interest was accrued
            blocks = blocks.sub(block.number.sub(cd.accrualBlockNumber()));
        }


    }
}