#[starknet::contract]
pub mod TokenSale {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_caller_address, get_contract_address};
    use crate::interfaces::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use crate::interfaces::itoken_sale::ITokenSale;

    component!(path: OwnableComponent, storage: owner, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: anything, event: UpgradeableEvent);

    // External impl
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal impl
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        accepted_payment_token: ContractAddress,
        token_price: Map<ContractAddress, u256>,
        tokens_available_for_sale: Map<ContractAddress, u256>,
        #[substorage(v0)]
        owner: OwnableComponent::Storage,
        #[substorage(v0)]
        anything: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, accepted_payment_token: ContractAddress,
    ) {
        self.owner.initializer(owner);
        self.accepted_payment_token.write(accepted_payment_token);
    }

    #[abi(embed_v0)]
    impl TokenSaleImpl of ITokenSale<ContractState> {
        fn check_available_token(self: @ContractState, token_address: ContractAddress) -> u256 {
            let token = IERC20Dispatcher { contract_address: token_address };

            let this_address = get_contract_address();

            return token.balance_of(this_address);
        }

        fn deposit_token(
            ref self: ContractState,
            token_address: ContractAddress,
            amount: u256,
            token_price: u256,
        ) {
            let caller = get_caller_address();
            let this_contract = get_contract_address();

            self.owner.assert_only_owner();

            let token = IERC20Dispatcher { contract_address: token_address };
            assert(token.balance_of(caller) > 0, 'insufficient balance');

            let transfer = token.transfer_from(caller, this_contract, amount);
            assert(transfer, 'transfer failed');

            self.tokens_available_for_sale.entry(token_address).write(amount);
            self.token_price.entry(token_address).write(token_price);
        }

        fn buy_token(ref self: ContractState, token_address: ContractAddress, amount: u256) {
            assert(
                self.tokens_available_for_sale.entry(token_address).read() == amount,
                'amount must be exact',
            );

            let buyer = get_caller_address();

            let payment_token = IERC20Dispatcher {
                contract_address: self.accepted_payment_token.read(),
            };
            let token_to_buy = IERC20Dispatcher { contract_address: token_address };

            let buyer_balance = payment_token.balance_of(buyer);
            let buying_price = self.token_price.entry(token_address).read();

            assert(buyer_balance >= buying_price, 'insufficient funds');
            payment_token.transfer_from(buyer, get_contract_address(), buying_price);
            let total_contract_balance = self.tokens_available_for_sale.entry(token_address).read();

            token_to_buy.transfer(buyer, total_contract_balance);
        }

        fn withdraw_token(ref self: ContractState) {
            self.owner.assert_only_owner();

            let caller = get_caller_address();
            let this_contract = get_contract_address();
            let payment_token = IERC20Dispatcher {
                contract_address: self.accepted_payment_token.read(),
            };
            let contract_balance = payment_token.balance_of(this_contract);

            if contract_balance > 0 {
                payment_token.transfer(caller, contract_balance);
            }
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.owner.assert_only_owner();

            self.anything.upgrade(new_class_hash);
        }

        fn get_tokens_available_for_sale(
            self: @ContractState, token_address: ContractAddress,
        ) -> u256 {
            self.tokens_available_for_sale.entry(token_address).read()
        }

        fn get_tokens_price(self: @ContractState, token_address: ContractAddress) -> u256 {
            self.token_price.entry(token_address).read()
        }
    }
}
