// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
contract MockFeed {
    int256 public answer = 250000000000; // $2500, 8 dec
    uint256 public age;
    function set(int256 a, uint256 ag) external { answer = a; age = ag; }
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80) {
        return (1, answer, block.timestamp - age, block.timestamp - age, 1);
    }
}
