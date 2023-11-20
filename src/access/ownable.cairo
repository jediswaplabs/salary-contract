use starknet::ContractAddress;

#[starknet::interface]
trait IOwnable<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;

    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    fn renounce_ownership(ref self: TContractState);
}

#[starknet::contract]
mod Ownable {
    use zeroable::Zeroable;

    // // locals
    use salary::access::ownable;
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    //
    // Storage
    //

    #[storage]
    struct Storage {
        _owner: ContractAddress
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred, 
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    //
    // Modifiers
    //

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_only_owner(self: @ContractState) {
            let owner = self._owner.read();
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Caller is the zero address');
            assert(caller == owner, 'Caller is not the owner');
        }
    }

    //
    // Ownable impl
    //

    #[external(v0)]
    impl IOwnableImpl of ownable::IOwnable<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            self._owner.read()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            assert(!new_owner.is_zero(), 'New owner is the zero address');
            self.assert_only_owner();
            self._transfer_ownership(new_owner);
        }

        fn renounce_ownership(ref self: ContractState) {
            self.assert_only_owner();
            self._transfer_ownership(Zeroable::zero());
        }
    }

    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(ref self: ContractState) {
            let caller = get_caller_address();
            self._transfer_ownership(caller);
        }

        fn _transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let previous_owner = self._owner.read();
            self._owner.write(new_owner);

            // Events
            self
                .emit(
                    Event::OwnershipTransferred(OwnershipTransferred { previous_owner, new_owner })
                );
        }
    }
}