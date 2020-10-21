require("dotenv").config();
const Web3 = require("web3");

const { mainnet: addresses } = require("./addresses");

const YearnCompDaiStrategy = require("./build/contracts/YearnCompDaiStrategy.json");

const IERC20 = require("./build/contracts/IERC20.json");
const CIERC20 = require("./build/contracts/cErc20I.json");

const ComptrollerI = require("./build/contracts/ComptrollerI.json");

const web3 = new Web3(new Web3("http://127.0.0.1:8545"));

const unlockAddress = "0x7a8edc710ddeadddb0b539de83f3a306a621e823";

const controllerAddress = "0x2be5d998c95de70d9a38b3d78e49751f10f9e88b";

const DAI = new web3.eth.Contract(IERC20.abi, addresses.tokens.dai);

const cDAI = new web3.eth.Contract(CIERC20.abi, addresses.tokens.cDai);

const COMP = new web3.eth.Contract(IERC20.abi, addresses.tokens.comp);

const Icompt = new web3.eth.Contract(
  ComptrollerI.abi,
  addresses.comptroller.Icomptroller
);

const AMOUNT_DEPOSIT_WEI = web3.utils.toWei((2000).toString()); // $2,000
const AMOUNT_WITHDRAW_WEI = web3.utils.toWei((1999).toString()); // $1999

const test = async () => {
  try {
    const networkId = await web3.eth.net.getId();

    const StrategyContract = new web3.eth.Contract(
      YearnCompDaiStrategy.abi,
      YearnCompDaiStrategy.networks[networkId].address
    );

    // -- Send 2000 DAI to the contract for testing deposit() method --
    await DAI.methods
      .transfer(StrategyContract.options.address, AMOUNT_DEPOSIT_WEI)
      .send({ from: unlockAddress });

    let tx = await StrategyContract.methods.deposit();

    const [gasPrice, gasCost] = await Promise.all([
      web3.eth.getGasPrice(),
      tx.estimateGas({ from: unlockAddress }),
    ]);

    let data = tx.encodeABI();

    const txData = {
      from: unlockAddress,
      to: StrategyContract.options.address,
      data,
      gas: gasCost,
      gasPrice,
    };

    const receipt = await web3.eth.sendTransaction(txData);

    console.log(`Transaction hash: ${receipt.transactionHash}`);

    const AFTER_DEPOSIT = {
      account_borrowable: await Icompt.methods
        .getAccountLiquidity(StrategyContract.options.address)
        .call(),
      dai_contract_bal: await DAI.methods
        .balanceOf(StrategyContract.options.address)
        .call(),
      cdai_contract_bal: await cDAI.methods
        .balanceOf(StrategyContract.options.address)
        .call(),
      current_pos: await StrategyContract.methods.getCurrentPosition().call(),
    };

    console.log(AFTER_DEPOSIT);

    // -- Test withdraw(uint256) method --
    tx = await StrategyContract.methods.withdraw(AMOUNT_WITHDRAW_WEI);

    data = tx.encodeABI();

    const txData_withdraw = {
      from: unlockAddress,
      to: StrategyContract.options.address,
      data,
      gas: 4100000,
      gasPrice,
    };

    const receipt_withdraw = await web3.eth.sendTransaction(txData_withdraw);

    console.log(`Transaction hash: ${receipt_withdraw.transactionHash}`);

    const AFTER_WITHDRAW = {
      account_borrowable: await Icompt.methods
        .getAccountLiquidity(StrategyContract.options.address)
        .call(),
      dai_contract_bal: await DAI.methods
        .balanceOf(StrategyContract.options.address)
        .call(),
      cdai_contract_bal: await cDAI.methods
        .balanceOf(StrategyContract.options.address)
        .call(),
      current_pos: await StrategyContract.methods.getCurrentPosition().call(),
    };

    console.log(AFTER_WITHDRAW);
  } catch (error) {
    console.log(error);
  }
};

test();
