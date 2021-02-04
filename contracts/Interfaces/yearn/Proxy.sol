// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface Proxy {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function increaseAmount(uint256) external;
}