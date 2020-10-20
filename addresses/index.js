const dydxMainnet = require("./dydx-mainnet.json");
const IcomptrollerMainnet = require("./icompt-mainnet.json");
const tokensMainnet = require("./tokens-mainnet.json");

module.exports = {
  mainnet: {
    dydx: dydxMainnet,
    tokens: tokensMainnet,
    comptroller: IcomptrollerMainnet,
  },
};
