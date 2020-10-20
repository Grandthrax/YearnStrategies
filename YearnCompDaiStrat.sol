pragma solidity ^0.6.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import './Interfaces/Compound/CErc20I.sol';
import './Interfaces/Compound/ComptrollerI.sol';
import './Interfaces/Compound/Exponential.sol';

import './Interfaces/UniswapInterfaces/IUniswapV2Router02.sol';

import "./Interfaces/Yearn/IController.sol";

import "./Interfaces/DyDx/DydxFlashLoanBase.sol";
import "./Interfaces/DyDx/ICallee.sol";


//this strategies template is taken from https://github.com/iearn-finance/yearn-starter-pack/tree/master/contracts/strategies/StrategyDAICurve.sol
contract YearnCompDaiStrategy is Exponential, DydxFlashloanBase, ICallee {
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

    uint256 public leverageTarget = 3700;

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
        uint256 _want = IERC20(want).balanceOf(address(this));

        //if we have no DAI nothing to be done
        if (_want > 0) {
            (uint256 position, bool deficit) = _calculateDesiredPosition(_want, true);
            //flash loan to position

         /*   IERC20(DAI).safeApprove(cDAI, 0);
            IERC20(DAI).safeApprove(cDAI, _want);
            CErc20I(cDAI).mint(_want);*/
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
        uint256 amount = balanceC();
        if (amount > 0) {
            _withdrawSome(balanceCInToken().sub(1));
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
        
        if (_comp > 0) {

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
        uint256 b = balanceC();
        uint256 bT = balanceCInToken();
        // can have unintentional rounding errors
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        uint256 _before = IERC20(want).balanceOf(address(this));
        _withdrawC(amount);
        uint256 _after = IERC20(want).balanceOf(address(this));
        uint256 _withdrew = _after.sub(_before);
        return _withdrew;
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function _withdrawC(uint256 amount) internal {
        CErc20I(cDAI).redeem(amount);
    }

    function balanceCInToken() public view returns (uint256) {
        // Mantisa 1e18 to decimals
        uint256 b = balanceC();
        if (b > 0) {
            b = b.mul(CTokenI(cDAI).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    function balanceC() public view returns (uint256) {
        return IERC20(cDAI).balanceOf(address(this));
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceCInToken());
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setCollateralTarget(uint256 target) external {
        require(msg.sender == strategist, "!strategist");
        require(target < 3990, "Target too close to 4x leverage");
        leverageTarget = target;
    }


    ///flash loan stuff

     function doFlashLoan(uint8 state, uint256 amount) internal{

    
        ISoloMargin solo = ISoloMargin(SOLO);

        uint256 marketId = _getMarketIdFromTokenAddress(SOLO, DAI);
     
        
        uint256 repayAmount = _getRepaymentAmountInternal(amount);
        // emit MyLog("Repaying ", repayAmount);
        IERC20 token = IERC20(DAI);

        token.safeApprove(SOLO, repayAmount);

        bytes memory data = abi.encode(state);


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

     }

    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public override {
        
        (uint8 _state) = abi.decode(data,(uint8));

        if(_state == 0){

        }else if(_state == 1){

        }

       

    }


    function _claimComp() internal {
      
        CTokenI[] memory tokens = new CTokenI[](1);
        tokens[0] =  CTokenI(cDAI);

        compound.claimComp(address(this), tokens);
    }


    //This function works out what we want to change with our flash loan
    function _calculateDesiredPosition(uint256 balance, bool dep) internal returns (uint256 position, bool deficit){
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        //we want to see how close to collateral target we are. 
        //So we take deposits. Add or remove balance and see what desired lend is. then make difference

        uint desiredBalance = 0;
        if(dep){
            desiredBalance = deposits.add(balance);
        }else{
            require(deposits > balance, "withdrawing more than balance");
            desiredBalance = deposits.sub(balance);
        }

        //desired borrow is balance x leveraged targed-1. So if we want 4x leverage (max allowed). we want to borrow 3x desired balance
        uint desiredBorrow = desiredBalance.mul(leverageTarget.sub(1000)).div(1000);


        //now we see if we want to add or remove balance
        // if the desired borrow is less than our current borrow we are in deficit. so we want to reduce position
        if(desiredBorrow < borrows){
            deficit = true;
            position = borrows - desiredBorrow;
        }else{
            //otherwise we want to increase position
             deficit = false;
            position = desiredBorrow - borrows;
        }

    }

    //returns the current position
    //WARNING - this returns just the balance at last time someone touched the cDAI token. 
    //Does not accrue interest. 
    function getCurrentPosition() public view returns (uint deposits, uint borrows){
        CErc20I cd =CErc20I(cDAI);

       
        (, uint ctokenBalance, uint borrowBalance, uint exchangeRate) = cd.getAccountSnapshot(address(this));
        borrows = borrowBalance;
        //copied from compound code
        (,deposits) = mulScalarTruncate(Exp({mantissa:exchangeRate}), ctokenBalance);

    }

}