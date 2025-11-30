// Minimal ERC20 interface used by ZpaceShip to call token functions
use starknet::ContractAddress;
use core::starknet::uint256::u256;

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}
// Minimal ERC20 interface used by ZpaceShip to call token functions
use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}
use core::starknet::uint256::u256;
