// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.15;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILovelyswapV2ERC20 is IERC20 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
