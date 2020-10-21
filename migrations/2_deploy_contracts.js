const YearnCompDaiStrat = artifacts.require("YearnCompDaiStrategy");

module.exports = function (deployer) {
  deployer.deploy(
    YearnCompDaiStrat,
    "0x24a42fD28C976A61Df5D00D0599C34c4f90748c8", // AAVE lending pool 
    "0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080" // Controller
  );
};
