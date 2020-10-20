const YearnCompDaiStrat = artifacts.require("YearnCompDaiStrategy");

module.exports = function (deployer) {
  deployer.deploy(
    YearnCompDaiStrat,
    "0x2be5d998c95de70d9a38b3d78e49751f10f9e88b"
  );
};
