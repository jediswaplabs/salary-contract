// @title Mesh Salary contract Cairo 2.2
// @author Mesh Finance
// @license MIT
// @notice Contract to disburse salary to contibutors

use starknet::ContractAddress;
use array::Array;

//
// External Interfaces
//

#[starknet::interface]
trait IERC20<T> {
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn balanceOf(self: @T, account: ContractAddress) -> u256; // TODO Remove after regenesis
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn transferFrom(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool; // TODO Remove after regenesis
}

#[starknet::interface]
trait IGuild<T> {
    fn get_contribution_tier(self: @T, contributor: ContractAddress) -> u32;
}

#[starknet::interface]
trait IMaster<T> {
    fn get_contributions_data(self: @T, contributor: ContractAddress, guild: felt252) -> Array<u32>;
    fn get_guild_total_contribution(self: @T, month_id: u32, guild: felt252) -> u32;
    fn get_guild_contribution_for_month(self: @T, contributor: ContractAddress, month_id: u32, guild: felt252) -> u32;


}

//
// Contract Interface
//
#[starknet::interface]
trait ISalaryDistributor2<TContractState> {
    // view functions
    fn token(self: @TContractState) -> ContractAddress;
    fn master(self: @TContractState) -> ContractAddress;
    fn guild_contract(self: @TContractState, guild: felt252) -> ContractAddress;
    fn get_total_effective_points(self: @TContractState, month_id: u32, guild: felt252) -> u32;
    fn get_claimable_salary(self: @TContractState, contributor: ContractAddress, month_ids: Array<u32>) -> u256;
    fn get_claimed_salary(self: @TContractState, contributor: ContractAddress) -> u256;

    // external functions
    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<felt252>);
    fn process_salary(ref self: TContractState, month_id: u32, guild: felt252, contributors: Array<ContractAddress>);
    fn claim_salary(ref self: TContractState, recipient: ContractAddress, month_ids: Array<u32>);


}

#[starknet::contract]
mod SalaryDistributor2 {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::ArrayTrait;
    // use salary::utils::erc20::ERC20;
    // use salary::utils::master::Master;
    // use salary::utils::guilds::devGuild::DevGuildSBT; // 
    use salary::access::ownable::{Ownable, IOwnable};
    use salary::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};

    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, IGuildDispatcher, IGuildDispatcherTrait, IMasterDispatcher, IMasterDispatcherTrait
    };

    // for debugging will remove after review
    use debug::PrintTrait;

    //
    // Storage Master
    //
    #[storage]
    struct Storage {
        _claimed_salary: LegacyMap::<ContractAddress, u256>, // @dev to be track of salary claimed by each contributor.
        _token: ContractAddress, // @dev token to paid out salary in
        _salary_pool: LegacyMap::<(u32, felt252), u256>, // @dev salary pool for specific month and guild
        _last_update_month_id_contributor: LegacyMap::<ContractAddress, u32>, // @dev to avoid unnecessary calculation of cum_salary
        _last_update_month_id: u32, // @dev to avoid unnecessary calculation of cum_salary
        _master: ContractAddress, // @dev master contract address
        _guilds: LegacyMap::<felt252, ContractAddress>, // @dev contract addresses for guild SBTs
        _tier_multiplier: LegacyMap::<u32, u32>, // @dev multiplier for each tier 
        _total_effective_points: LegacyMap::<(u32, felt252), u32>, // @dev processed salary for guilds for specific month id
        _contributor_effective_points: LegacyMap::<(u32, felt252, ContractAddress), u32>, // @dev processed salary for contributors for specifoc guilds and month id
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SalaryPoolUpdated: SalaryPoolUpdated,
        SalaryClaimed: SalaryClaimed,
        SalaryProcessed: SalaryProcessed,
    }

    // @notice An event emitted whenever funds are added to salary pool.
    #[derive(Drop, starknet::Event)]
    struct SalaryPoolUpdated {
        month_id: u32, 
        guild: felt252,
        pool_amount: u256
    }

    // @notice An event emitted whenever contribution claims salary
    #[derive(Drop, starknet::Event)]
    struct SalaryClaimed {
        month_id: u32,
        amount: u256,
        recipient: ContractAddress
    }

    // @notice An event emitted whenever Salary is processed
    #[derive(Drop, starknet::Event)]
    struct SalaryProcessed {
        month_id: u32,
        guild: felt252,
        total_effective_points: u32
    }
    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner_: ContractAddress, token_: ContractAddress, master_: ContractAddress, guilds_: Array<ContractAddress>) {
        self._token.write(token_); // USDC
        // self._token.write(contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()); // USDC
        self._master.write(master_);
        self._guilds.write('dev', *guilds_[0]);
        self._guilds.write('design', *guilds_[1]);
        self._guilds.write('problem_solving', *guilds_[2]);
        self._guilds.write('marcom', *guilds_[3]);
        self._guilds.write('research', *guilds_[4]);

        self._tier_multiplier.write(0, 0);
        self._tier_multiplier.write(1, 1000);
        self._tier_multiplier.write(2, 1200);
        self._tier_multiplier.write(3, 1350);
        self._tier_multiplier.write(4, 1600);
        self._tier_multiplier.write(5, 1750);

        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner_);

    }

    #[external(v0)]
    impl SalaryDistributor2 of super::ISalaryDistributor2<ContractState> {
        //
        // Getters
        //
        fn token(self: @ContractState) -> ContractAddress {
            self._token.read()
        }

        fn master(self: @ContractState) -> ContractAddress {
            self._master.read()
        }

        fn guild_contract(self: @ContractState, guild: felt252) -> ContractAddress {
            // self._guilds.read(guild).print();
            self._guilds.read(guild)
        }

        fn get_total_effective_points(self: @ContractState, month_id: u32, guild: felt252) -> u32 {
            // self._total_effective_points.read((month_id, guild)).print();
            self._total_effective_points.read((month_id, guild))
        }

        fn get_claimable_salary(self: @ContractState, contributor: ContractAddress, month_ids: Array<u32>) -> u256 {
            let mut salary = 0_u256;
            let mut current_index = 0_u32;

            loop {
                if (current_index == month_ids.len()){
                    break;
                }
                salary += InternalImpl::_get_guild_claimable_salary(self, contributor, *month_ids[current_index], 'dev');
                salary += InternalImpl::_get_guild_claimable_salary(self, contributor, *month_ids[current_index], 'design');
                salary += InternalImpl::_get_guild_claimable_salary(self, contributor, *month_ids[current_index], 'problem_solving');
                salary += InternalImpl::_get_guild_claimable_salary(self, contributor, *month_ids[current_index], 'marcom');
                salary += InternalImpl::_get_guild_claimable_salary(self, contributor, *month_ids[current_index], 'research');

                current_index += 1;
                // salary.print();
            };

            salary
        }

        fn get_claimed_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            self._claimed_salary.read(contributor)
        }

        //
        // Setters
        //

        fn add_fund_to_salary_pools(ref self: ContractState, month_id: u32, amounts: Array<u256>, guilds: Array<felt252>) {
            self._only_owner();
            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let mut amount_to_transfer = 0_u256;
            let mut current_index = 0_u32;
            assert(guilds.len() == amounts.len(), 'INVALID_INPUT');
            loop {
                if (current_index == guilds.len()) {
                    break;
                }
                let pool_amount = self._salary_pool.read((month_id, *guilds[current_index]));
                assert (pool_amount == 0, 'ALREADY_SET');
                amount_to_transfer += *amounts[current_index];
                self._salary_pool.write((month_id, *guilds[current_index]), *amounts[current_index]);

                self.emit(SalaryPoolUpdated{month_id: month_id, guild: *guilds[current_index], pool_amount: *amounts[current_index]});
                current_index += 1;
            };
            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            tokenDispatcher.transfer_from(caller, contract_address, amount_to_transfer);
            self._last_update_month_id.write(month_id);
        }

        fn process_salary(ref self: ContractState, month_id: u32, guild: felt252, contributors: Array<ContractAddress>) {
            let processed_salary = self._total_effective_points.read((month_id, guild));
            assert(processed_salary == 0, 'ALREADY_PROCESSED');

            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            let guild_address = self._guilds.read(guild);
            // guild_address.print();
            let guildDispatcher = IGuildDispatcher { contract_address: guild_address };
            let mut total_contribution = 0_u32;
            let mut total_effective_points = 0_u32;
            let mut current_index = 0_u32;
            loop {
                if (current_index == contributors.len()) {
                    break;
                }
                let points_earned = masterDispatcher.get_guild_contribution_for_month(*contributors[current_index], month_id, guild);
                let contributor_tier = guildDispatcher.get_contribution_tier(*contributors[current_index]);
                // contributor_tier.print();
                let multiplier = self._tier_multiplier.read(contributor_tier);
                let effective_points = (points_earned * multiplier) / 1000; // multiplier have Precision of 1000
                // effective_points.print();
                total_contribution += points_earned;
                total_effective_points += effective_points;

                self._contributor_effective_points.write((month_id, guild,*contributors[current_index]), effective_points);
                current_index += 1;

            };

            let actual_total_contribution = masterDispatcher.get_guild_total_contribution(month_id, guild);
            assert(total_contribution == actual_total_contribution, 'INCORRECT_CONTRIBUTORS_LIST');
            
            self._total_effective_points.write((month_id, guild), total_effective_points);
            self.emit(SalaryProcessed{month_id: month_id, guild: guild, total_effective_points: total_effective_points});
        }

        fn claim_salary(ref self: ContractState, recipient: ContractAddress, month_ids: Array<u32>) {
            let contributor = get_caller_address();

            let mut claimable_salary = 0_u256;
            let mut current_index = 0_u32;

            loop {
                if (current_index == month_ids.len()){
                    break;
                }
                let mut monthly_salary = 0_u256;
                monthly_salary += InternalImpl::_calculate_guild_claimable_salary(ref self, contributor, *month_ids[current_index], 'dev');
                monthly_salary += InternalImpl::_calculate_guild_claimable_salary(ref self, contributor, *month_ids[current_index], 'design');
                monthly_salary += InternalImpl::_calculate_guild_claimable_salary(ref self, contributor, *month_ids[current_index], 'problem_solving');
                monthly_salary += InternalImpl::_calculate_guild_claimable_salary(ref self, contributor, *month_ids[current_index], 'marcom');
                monthly_salary += InternalImpl::_calculate_guild_claimable_salary(ref self, contributor, *month_ids[current_index], 'research');

                self.emit(SalaryClaimed{month_id: *month_ids[current_index], amount: monthly_salary, recipient: recipient});
                claimable_salary += monthly_salary;
                current_index += 1;
            };

            assert(claimable_salary > 0, 'ZERO_CLAIMABLE_AMOUNT');
            let claimed_salary = self._claimed_salary.read(contributor);
            self._claimed_salary.write(contributor, claimed_salary + claimable_salary);

            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            tokenDispatcher.transfer(recipient, claimable_salary);

        }

        

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _calculate_guild_claimable_salary(ref self: ContractState, contributor: ContractAddress, month_id: u32, guild: felt252) -> u256 {
            let mut claimable_salary = 0_u256;
            let total_effective_points = self._total_effective_points.read((month_id, guild)).into();
            let effective_points = self._contributor_effective_points.read((month_id, guild, contributor)).into();
            if (effective_points > 0 && total_effective_points > 0) {// salary have been processed and can ready to be claim.
                let salary_pool = self._salary_pool.read((month_id, guild));
                claimable_salary = (effective_points * salary_pool) / total_effective_points;
                // updating to avoid multiple claiming
                self._contributor_effective_points.write((month_id, guild, contributor), 0);
            }
            claimable_salary
        }

        fn _get_guild_claimable_salary(self: @ContractState, contributor: ContractAddress, month_id: u32, guild: felt252) -> u256 {
            let mut claimable_salary = 0_u256;
            let total_effective_points = self._total_effective_points.read((month_id, guild)).into();
            let effective_points = self._contributor_effective_points.read((month_id, guild, contributor)).into();
            // effective_points.print();
            // total_effective_points.print();
            if (effective_points > 0 && total_effective_points > 0) {// salary have been processed and can ready to be claim.
                let salary_pool = self._salary_pool.read((month_id, guild));
                claimable_salary = (effective_points * salary_pool) / total_effective_points;
            }
            // claimable_salary.print();
            claimable_salary
        }

    }

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn _only_owner(self: @ContractState) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.assert_only_owner();
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