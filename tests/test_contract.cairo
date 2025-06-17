use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, get_class_hash, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress};
use token_sale::interfaces::itoken_sale::{ITokenSaleDispatcher, ITokenSaleDispatcherTrait};

// ETH token address on Starknet
const ACCEPTED_PAYMENT_TOKEN: ContractAddress =
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
    .try_into()
    .unwrap();

// STRK token address on Starknet
const TOKEN_TO_BUY: ContractAddress =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
    .try_into()
    .unwrap();

const PRICE: u256 = 21000;

const OWNER: ContractAddress = 0x007e9244c7986db5e807d8838bcc218cd80ad4a82eb8fd1746e63fe223f67411
    .try_into()
    .unwrap();

const BROKE_OWNER: ContractAddress = 12.try_into().unwrap();

const NON_OWNER_WITH_BALANCE: ContractAddress =
    0x000ed03da7bc876b74d81fe91564f8c9935a2ad2e1a842a822b4909203c8e796
    .try_into()
    .unwrap();

const NON_OWNER_WITHOUT_BALANCE: ContractAddress = 0x789.try_into().unwrap();

// Helper function to deploy the contract
fn deploy_token_sale_contract() -> (ITokenSaleDispatcher, IERC20Dispatcher, IERC20Dispatcher) {
    let contract = declare("TokenSale").unwrap();

    let mut constructor_args = array![];
    Serde::serialize(@OWNER, ref constructor_args);
    Serde::serialize(@ACCEPTED_PAYMENT_TOKEN, ref constructor_args);

    let (contract_address, _err) = contract.contract_class().deploy(@constructor_args).unwrap();

    let token_sale_dispatcher = ITokenSaleDispatcher { contract_address };
    let eth_dispatcher = IERC20Dispatcher { contract_address: ACCEPTED_PAYMENT_TOKEN };
    let strk_dispatcher = IERC20Dispatcher { contract_address: TOKEN_TO_BUY };

    (token_sale_dispatcher, eth_dispatcher, strk_dispatcher)
}

// Helper function to deploy the contract
fn deploy_token_sale_contract_with_broke_owner() -> (
    ITokenSaleDispatcher, IERC20Dispatcher, IERC20Dispatcher,
) {
    let contract = declare("TokenSale").unwrap();

    let mut constructor_args = array![];
    Serde::serialize(@BROKE_OWNER, ref constructor_args);
    Serde::serialize(@ACCEPTED_PAYMENT_TOKEN, ref constructor_args);

    let (contract_address, _err) = contract.contract_class().deploy(@constructor_args).unwrap();

    let token_sale_dispatcher = ITokenSaleDispatcher { contract_address };
    let eth_dispatcher = IERC20Dispatcher { contract_address: ACCEPTED_PAYMENT_TOKEN };
    let strk_dispatcher = IERC20Dispatcher { contract_address: TOKEN_TO_BUY };

    (token_sale_dispatcher, eth_dispatcher, strk_dispatcher)
}

#[test]
fn test_constructor_initializes_state() {
    let (dispatcher, _, _) = deploy_token_sale_contract();

    assert(dispatcher.contract_address.is_non_zero(), 'Deployment paniced');
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'Caller is not the owner')]
fn test_deposit_token_should_panic_when_caller_is_not_owner() {
    let amount = 1000;

    let (dispatcher, _, _) = deploy_token_sale_contract();

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);

    dispatcher.deposit_token(TOKEN_TO_BUY, amount, PRICE);

    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'insufficient balance')]
fn test_deposit_token_should_panic_when_caller_balance_is_low() {
    let (dispatcher, _, _) = deploy_token_sale_contract_with_broke_owner();
    let amount = 1000;

    start_cheat_caller_address(dispatcher.contract_address, BROKE_OWNER);

    dispatcher.deposit_token(TOKEN_TO_BUY, amount, PRICE);

    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_deposit_token() {
    let amount = 1000;

    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);

    strk_dispatcher.approve(dispatcher.contract_address, amount);

    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);

    let caller_balance_before = strk_dispatcher.balance_of(OWNER);
    let contract_balance_before = dispatcher.check_available_token(TOKEN_TO_BUY);

    dispatcher.deposit_token(TOKEN_TO_BUY, amount, PRICE);

    stop_cheat_caller_address(dispatcher.contract_address);

    let caller_balance_after = strk_dispatcher.balance_of(OWNER);
    let contract_balance_after = dispatcher.check_available_token(TOKEN_TO_BUY);

    assert(caller_balance_after == caller_balance_before - amount, 'Incorrect amount');
    assert(contract_balance_after == contract_balance_before + amount, 'Incorrect amount');
    assert(dispatcher.get_tokens_available_for_sale(TOKEN_TO_BUY) == amount, 'Incorrect amount');
    assert(dispatcher.get_tokens_price(TOKEN_TO_BUY) == PRICE, 'Incorrect price');
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'amount must be exact')]
fn test_buy_token_incorrect_amount_should_panic() {
    let buying_amount = 500;

    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);

    strk_dispatcher.approve(dispatcher.contract_address, buying_amount);

    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);

    dispatcher.buy_token(ACCEPTED_PAYMENT_TOKEN, buying_amount);

    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'insufficient funds')]
fn test_buy_token_with_insufficient_fund_should_panic() {
    let deposited_amount = 500;
    let buying_amount = 500;

    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);

    strk_dispatcher.approve(dispatcher.contract_address, deposited_amount);

    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);

    dispatcher.deposit_token(TOKEN_TO_BUY, deposited_amount, PRICE);

    stop_cheat_caller_address(dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITHOUT_BALANCE);

    dispatcher.buy_token(TOKEN_TO_BUY, buying_amount);

    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_buy_token() {
    let deposited_amount = 500;
    let buying_amount = 500;

    let (dispatcher, eth_dispatcher, strk_dispatcher) = deploy_token_sale_contract();

    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);

    strk_dispatcher.approve(dispatcher.contract_address, deposited_amount);

    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);

    dispatcher.deposit_token(TOKEN_TO_BUY, deposited_amount, PRICE);

    stop_cheat_caller_address(dispatcher.contract_address);

    start_cheat_caller_address(eth_dispatcher.contract_address, NON_OWNER_WITH_BALANCE);

    eth_dispatcher.approve(dispatcher.contract_address, PRICE);

    stop_cheat_caller_address(eth_dispatcher.contract_address);

    let caller_eth_balance_before = eth_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let caller_strk_balance_before = strk_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let contract_eth_balance_before = eth_dispatcher.balance_of(dispatcher.contract_address);
    let contract_strk_balance_before = strk_dispatcher.balance_of(dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);

    dispatcher.buy_token(TOKEN_TO_BUY, buying_amount);

    stop_cheat_caller_address(dispatcher.contract_address);

    let caller_eth_balance_after = eth_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let caller_strk_balance_after = strk_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let contract_eth_balance_after = eth_dispatcher.balance_of(dispatcher.contract_address);
    let contract_strk_balance_after = strk_dispatcher.balance_of(dispatcher.contract_address);

    assert(caller_eth_balance_after == caller_eth_balance_before - PRICE, 'Invalid ETH amount');
    assert(
        caller_strk_balance_after == caller_strk_balance_before + deposited_amount,
        'Invalid STRK amount',
    );
    assert(contract_eth_balance_after == contract_eth_balance_before + PRICE, 'Invalid ETH amount');
    assert(
        contract_strk_balance_after == contract_strk_balance_before - deposited_amount,
        'Invalid STRK amount',
    );
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'Caller is not the owner')]
fn test_upgrade_should_panic_when_caller_is_not_owner() {
    let new_class_hash: ClassHash = 112233.try_into().unwrap();

    let (dispatcher, _, _) = deploy_token_sale_contract();

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);

    dispatcher.upgrade(new_class_hash);

    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
fn test_upgrade() {
    let new_class_hash: ClassHash = *declare("TokenSale").unwrap().contract_class().class_hash;

    let (dispatcher, _, _) = deploy_token_sale_contract();

    start_cheat_caller_address(dispatcher.contract_address, OWNER);

    dispatcher.upgrade(new_class_hash);

    stop_cheat_caller_address(dispatcher.contract_address);

    let class_hash = get_class_hash(dispatcher.contract_address);

    assert(class_hash == new_class_hash, 'Invalid class hash');
}
