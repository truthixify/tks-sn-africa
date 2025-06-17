use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait ITokenSale<TContractState> {
    fn check_available_token(self: @TContractState, token_address: ContractAddress) -> u256;

    fn deposit_token(
        ref self: TContractState, token_address: ContractAddress, amount: u256, token_price: u256,
    );

    fn buy_token(ref self: TContractState, token_address: ContractAddress, amount: u256);

    fn withdraw_token(ref self: TContractState);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);

    fn get_tokens_available_for_sale(self: @TContractState, token_address: ContractAddress) -> u256;

    fn get_tokens_price(self: @TContractState, token_address: ContractAddress) -> u256;
}
