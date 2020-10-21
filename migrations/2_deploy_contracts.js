const YearnCompDaiStrat = artifacts.require("YearnCompDaiStrategy");

module.exports = function (deployer) {
  deployer.deploy(
    YearnCompDaiStrat,
    "0x2be5d998c95de70d9a38b3d78e49751f10f9e88b"
    // "0x7a8edc710ddeadddb0b539de83f3a306a621e823" --> Use following address to mockup controller as it has good balace of ETH & DAI
  );
};
