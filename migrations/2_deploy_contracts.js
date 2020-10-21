const YearnCompDaiStrat = artifacts.require("YearnCompDaiStrategy");

module.exports = function (deployer) {
  deployer.deploy(
    YearnCompDaiStrat,
    "0x7a8edc710ddeadddb0b539de83f3a306a621e823"
  );
};
