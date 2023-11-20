// @title Mesh Guild SBTs Cairo 2.2
// @author Mesh Finance
// @license MIT
// @notice SBT contract to give out to contributor

use starknet::ContractAddress;
use array::Array;


#[starknet::interface]
trait IMaster<T> {
    fn get_guild_points(self: @T, contributor: ContractAddress, guild: felt252) -> u32;
}

//
// Contract Interface
//
#[starknet::interface]
trait IMarcomGuildSBT<TContractState> {
    // view functions
    fn tokenURI(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn tokenURI_from_contributor(self: @TContractState, contributor: ContractAddress) -> Span<felt252>;
    fn get_master(self: @TContractState) -> ContractAddress;
    fn get_next_token_id(self: @TContractState) -> u256;
    fn get_contribution_tier(self: @TContractState, contributor: ContractAddress) -> u32;
    fn get_contribution_levels(self: @TContractState) -> Array<u32>;
    fn get_number_of_levels(self: @TContractState) -> u32;
    fn baseURI(self: @TContractState) -> Span<felt252>;
    fn wallet_of_owner(self: @TContractState, account: ContractAddress) -> u256;

    // external functions
    fn update_baseURI(ref self: TContractState, new_baseURI: Span<felt252>);
    fn update_contribution_levels(ref self: TContractState, new_conribution_levels: Array<u32>);
    fn update_master(ref self: TContractState, new_master: ContractAddress);
    fn safe_mint(ref self: TContractState, token_type: u8);
    fn migrate_sbt(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);

}

#[starknet::contract]
mod MarcomGuildSBT {

    use option::OptionTrait;
    // use traits::Into;
    use array::{SpanSerde, ArrayTrait};
    use clone::Clone;
    use array::SpanTrait;
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use zeroable::Zeroable;
    use openzeppelin::token::erc721::ERC721;
    use openzeppelin::token::erc721::ERC721::InternalTrait as ERC721InternalTrait;

    use openzeppelin::introspection::interface::ISRC5;
    use openzeppelin::introspection::interface::ISRC5Camel;
    use openzeppelin::token::erc721::interface::{
        IERC721, IERC721CamelOnly, IERC721Metadata, IERC721MetadataCamelOnly
    };
    use salary::access::ownable::{Ownable, IOwnable};
    use salary::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    // use alexandria_storage::list::{List, ListTrait};
    use salary::utils::storage::StoreSpanFelt252;
    use salary::utils::array::StoreU32Array;
    use super::{
        IMasterDispatcher, IMasterDispatcherTrait
    };

    const IERC721_ID_LEGACY: felt252 = 0x80ac58cd;
    const IERC721_METADATA_ID_LEGACY: felt252 = 0x5b5e139f;
    const IERC721_RECEIVER_ID_LEGACY: felt252 = 0x150b7a02;

    #[storage]
    struct Storage {
        _master: ContractAddress,
        _contribution_levels: Array<u32>,
        _baseURI: Span<felt252>,
        _token_type: LegacyMap::<ContractAddress, u8>,
        _next_token_id: u256,
        _wallet_of_owner: LegacyMap::<ContractAddress, u256>,
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, name_: felt252, symbol_: felt252, baseURI_: Span<felt252>, owner_: ContractAddress, master_: ContractAddress, contribution_levels_: Array<u32>) {
        let mut erc721_self = ERC721::unsafe_new_contract_state();
        erc721_self.initializer(name: name_, symbol: symbol_);

        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner_);

        self._baseURI.write(baseURI_);
        self._master.write(master_);
        self._next_token_id.write(1);
        InternalImpl::_update_contribution_levels(ref self, contribution_levels_);
    }

    #[external(v0)]
    impl MarcomGuildSBT of super::IMarcomGuildSBT<ContractState> {
        //
        // Getters
        //
        fn tokenURI(self: @ContractState, token_id: u256) -> Span<felt252> {
            let erc721_self = ERC721::unsafe_new_contract_state();
            let owner = erc721_self.owner_of(:token_id);
            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            // @notice this is a sample SBT contract for marcom guild, update the next line before deploying other guild
            let points = masterDispatcher.get_guild_points(owner, 'marcom');
            let token_type = self._token_type.read(owner);

            let tier = InternalImpl::_get_contribution_tier(self, points);

            InternalImpl::_get_tokenURI(self, tier, token_type)

        }



        fn tokenURI_from_contributor(self: @ContractState, contributor: ContractAddress) -> Span<felt252> {
            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            // @notice this is a sample SBT contract for marcom guild, update the next line before deploying other guild
            let points = masterDispatcher.get_guild_points(contributor, 'marcom');
            let token_type = self._token_type.read(contributor);

            let tier = InternalImpl::_get_contribution_tier(self, points);

            InternalImpl::_get_tokenURI(self, tier, token_type)

        }


        fn get_master(self: @ContractState) -> ContractAddress {
            self._master.read()
        }

        fn get_next_token_id(self: @ContractState) -> u256 {
            self._next_token_id.read()
        }


        fn get_contribution_tier(self: @ContractState, contributor: ContractAddress) -> u32 {
            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            let points = masterDispatcher.get_guild_points(contributor, 'marcom');
            InternalImpl::_get_contribution_tier(self, points)
        }


        fn get_contribution_levels(self: @ContractState) -> Array<u32> {
            self._contribution_levels.read()
        }

        fn get_number_of_levels(self: @ContractState) -> u32 {
            self._contribution_levels.read().len()
        }

        fn baseURI(self: @ContractState) -> Span<felt252> {
            self._baseURI.read()
        }

        fn wallet_of_owner(self: @ContractState, account: ContractAddress) -> u256 {
            self._wallet_of_owner.read(account)
        }


        //
        // Setters
        //

        fn update_baseURI(ref self: ContractState, new_baseURI: Span<felt252>) {
            self._only_owner();
            self._baseURI.write(new_baseURI);
        }

        fn update_contribution_levels(ref self: ContractState, new_conribution_levels: Array<u32>) {
            self._only_owner();
            InternalImpl::_update_contribution_levels(ref self, new_conribution_levels);

        }
        fn update_master(ref self: ContractState, new_master: ContractAddress) {
            self._only_owner();
            self._master.write(new_master);
        }

        fn safe_mint(ref self: ContractState, token_type: u8) {
            let account = get_caller_address();
            let mut erc721_self = ERC721::unsafe_new_contract_state();

            let balance = erc721_self.balance_of(:account);
            assert (balance == 0, 'ALREADY_MINTED');

            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            let points = masterDispatcher.get_guild_points(account, 'marcom');
            let tier = InternalImpl::_get_contribution_tier(@self, points);

            assert (tier != 0, 'NOT_ENOUGH_POINTS');
            self._token_type.write(account, token_type);
            let token_id = self._next_token_id.read();
            erc721_self._mint(to: account, token_id: token_id.into());
            self._wallet_of_owner.write(account, token_id);
            self._next_token_id.write(token_id + 1);

        }

        fn migrate_sbt(ref self: ContractState, old_address: ContractAddress, new_address: ContractAddress) {
            self._only_master();
            let mut erc721_self = ERC721::unsafe_new_contract_state();

            let old_address_balance = erc721_self.balance_of(account: old_address);
            if (old_address_balance == 0) {
                return ();
            }

            let new_address_balance = erc721_self.balance_of(account: new_address);
            assert (new_address_balance == 0, 'SBT_ALREADY_FOUND');

            let token_id = self._wallet_of_owner.read(old_address);
            let token_type = self._token_type.read(old_address);

            erc721_self._transfer(from: old_address, to: new_address, :token_id);

            self._wallet_of_owner.write(old_address, 0);
            self._wallet_of_owner.write(new_address, token_id);
            self._token_type.write(new_address, token_type);

        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _update_contribution_levels(ref self: ContractState, new_contribution_levels: Array<u32>) {
            self._contribution_levels.write(new_contribution_levels);
        }

        fn _get_contribution_tier(self: @ContractState, points: u32) -> u32 {
            let mut current_index = 0_u32;
            let contribution_levels = self._contribution_levels.read();
            loop {
                if (current_index == contribution_levels.len()) {
                    break;
                }

                if (points < *contribution_levels[current_index]) {
                    break;
                }

                current_index += 1;
            };
            current_index
        }

        fn _get_tokenURI(self: @ContractState, tier: u32, token_type: u8) -> Span<felt252> {
            let baseURI = self._baseURI.read();
            let new_base_uri: Array<felt252> = baseURI.snapshot.clone();
            let mut tmp: Array<felt252> = InternalImpl::append_number_ascii(new_base_uri, tier.into());
            tmp = InternalImpl::append_number_ascii(tmp, token_type.into());
            tmp.append('.json');
            return tmp.span();
        }



        fn append_number_ascii(mut uri: Array<felt252>, mut number_in: u256) -> Array<felt252> {
            // TODO: replace with u256 divide once it's implemented on network
            let mut number: u128 = number_in.try_into().unwrap();
            let mut tmpArray: Array<felt252> = ArrayTrait::new();
            loop {
                if (number == 0.try_into().unwrap()) {
                    break;
                }
                let digit: u128 = number % 10;
                number /= 10;
                tmpArray.append(digit.into() + 48);
            };
            let mut i: u32 = tmpArray.len();
            if (i == 0.try_into().unwrap()) { // deal with 0 case
                uri.append(48);
            }
            loop {
                if i == 0.try_into().unwrap() {
                    break;
                }
                i -= 1;
                uri.append(*tmpArray.get(i.into()).unwrap().unbox());
            };
            return uri;
        }
    }
    

    //
    // ERC721 ABI impl
    //

    #[external(v0)]
    impl IERC721Impl of IERC721<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.balance_of(:account)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.owner_of(:token_id)
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.get_approved(:token_id)
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.is_approved_for_all(:owner, :operator)
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let mut erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.approve(:to, :token_id);
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            assert(false, 'SBT_NOT_TRANSFERABLE');
            // let mut erc721_self = ERC721::unsafe_new_contract_state();

            // erc721_self.transfer_from(:from, :to, :token_id);
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            assert(false, 'SBT_NOT_TRANSFERABLE');

            // let mut erc721_self = ERC721::unsafe_new_contract_state();

            // erc721_self.safe_transfer_from(:from, :to, :token_id, :data);
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let mut erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.set_approval_for_all(:operator, :approved);
        }
    }

    #[external(v0)]
    impl ISRC5Impl of ISRC5<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            if ((interface_id == IERC721_ID_LEGACY)
                | (interface_id == IERC721_METADATA_ID_LEGACY)) {
                true
            } else {
                let mut erc721_self = ERC721::unsafe_new_contract_state();
                erc721_self.supports_interface(:interface_id)
            }
        }
    }

    #[external(v0)]
    impl ISRC5CamelImpl of ISRC5Camel<ContractState> {
        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            self.supports_interface(interface_id: interfaceId)
        }
    }

    #[external(v0)]
    impl IERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.name()
        }

        fn symbol(self: @ContractState) -> felt252 {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.symbol()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            let erc721_self = ERC721::unsafe_new_contract_state();

            erc721_self.token_uri(:token_id)
        }
    }

    #[external(v0)]
    impl JediERC721CamelImpl of IERC721CamelOnly<ContractState> {
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            IERC721::balance_of(self, account: account)
        }

        fn ownerOf(self: @ContractState, tokenId: u256) -> ContractAddress {
            IERC721::owner_of(self, token_id: tokenId)
        }

        fn getApproved(self: @ContractState, tokenId: u256) -> ContractAddress {
            IERC721::get_approved(self, token_id: tokenId)
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            IERC721::is_approved_for_all(self, owner: owner, operator: operator)
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
        ) {
            assert(false, 'SBT_NOT_TRANSFERABLE');

            // IERC721::transfer_from(ref self, :from, :to, token_id: tokenId);
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            data: Span<felt252>
        ) {
            assert(false, 'SBT_NOT_TRANSFERABLE');

            // IERC721::safe_transfer_from(ref self, :from, :to, token_id: tokenId, :data);
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            IERC721::set_approval_for_all(ref self, :operator, :approved);
        }
    }


    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn _only_owner(self: @ContractState) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.assert_only_owner();
        }

        fn _only_master(self: @ContractState) {
            let master = self._master.read();
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'CALLER_IS_ZERO_ADDRESS');
            assert (caller == master, 'UNAUTHORISED')
        }
    }

    #[external(v0)]
    impl IOwnableImpl of IOwnable<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            let ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.owner()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.transfer_ownership(:new_owner);
        }

        fn renounce_ownership(ref self: ContractState) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.renounce_ownership();
        }
    }

}

