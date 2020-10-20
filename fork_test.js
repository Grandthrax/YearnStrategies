require("dotenv").config();
const Web3 = require("web3");

const { mainnet: addresses } = require("./addresses");

const YearnCompDaiStrategy = require("./build/contracts/YearnCompDaiStrategy.json");

const IERC20 = require("./build/contracts/IERC20.json");
const CIERC20 = require("./build/contracts/cErc20I.json");

const ComptrollerI = require("./build/contracts/ComptrollerI.json");

const web3 = new Web3(new Web3("http://127.0.0.1:8545"));

const unlockAddress = "0x7a8edc710ddeadddb0b539de83f3a306a621e823";

const DAI = new web3.eth.Contract(IERC20.abi, addresses.tokens.dai);

const cDAI = new web3.eth.Contract(CIERC20.abi, addresses.tokens.cDai);

const COMP = new web3.eth.Contract(IERC20.abi, addresses.tokens.comp);

const Icompt = new web3.eth.Contract(
  ComptrollerI.abi,
  addresses.comptroller.Icomptroller
);

const AMOUNT_DEPOSIT_WEI = web3.utils.toWei((2000).toString()); // $2,000

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

    const tx = await StrategyContract.methods.deposit();

    const [gasPrice, gasCost] = await Promise.all([
      web3.eth.getGasPrice(),
      tx.estimateGas({ from: unlockAddress }),
    ]);

    const data = tx.encodeABI();

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
  } catch (error) {
    console.log(error);
  }
};

test();
