pragma solidity >=0.5.16;

import "./CTokenI.sol";
interface CEtherI is CTokenI{
    function redeemUnderlying(uint redeemAmount) external returns (uint);
      function redeem(uint redeemTokens) external returns (uint);
    function liquidateBorrow(address borrower, CTokenI cTokenCollateral) external payable;
    function mint() external payable;
}