const YearnCompDaiStrat = artifacts.require("YearnCompDaiStrategy");

module.exports = function (deployer) {
  deployer.deploy(
    YearnCompDaiStrat,
    "0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080" // Controller
  );
};
