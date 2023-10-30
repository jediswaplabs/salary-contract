// @title Mesh Salary contract Cairo 2.2
// @author Mesh Finance
// @license MIT
// @notice Contract to disburse salary to contibutors

use starknet::ContractAddress;
use array::Array;

#[derive(Drop, Serde, starknet::Store)]
struct Salary {
    // @notice contributor salary earned so far
    cum_salary: u256,
    // @notice salary claimed so far
    claimed_salary: u256
}

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
    // fn get_total_contribution(self: @T, month_id: u32) -> TotalMonthlyContribution;
    // fn get_contributions_points(self: @T, contributor: ContractAddress) -> Contribution;
    fn get_contributions_data(self: @T, contributor: ContractAddress, guild: felt252) -> Array<u32>;
    fn get_guild_total_contribution(self: @T, month_id: u32, guild: felt252) -> u32;
    fn get_guild_points(self: @T, contributor: ContractAddress, guild: felt252) -> u32;


}

//
// Contract Interface
//
#[starknet::interface]
trait ISalaryDistributor<TContractState> {
    // view functions
    fn token(self: @TContractState) -> ContractAddress;
    fn master(self: @TContractState) -> ContractAddress;
    fn get_cum_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    fn get_claimed_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    // fn get_cum_salarys(self: @TContractState, contributor: ContractAddress);


    // external functions
    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<felt252>);
    fn update_cum_salary(ref self: TContractState, contributor: ContractAddress);
    fn claim_salary(ref self: TContractState, recipient: ContractAddress);


}

#[starknet::contract]
mod SalaryDistributor {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::ArrayTrait;
    use salary::utils::erc20::ERC20;
    use salary::utils::master::Master;
    use salary::utils::guildSBT::GuildSBT;
    use salary::access::ownable::{Ownable, IOwnable};
    use salary::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};
    use super::Salary;

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
        _salary: LegacyMap::<ContractAddress, Salary>, // @dev salary for each contributor
        _token: ContractAddress, // @dev token to paid out salary in
        _salary_pool: LegacyMap::<(u32, felt252), u256>, // @dev salary pool for specific month and guild
        _last_update_month_id_contributor: LegacyMap::<ContractAddress, u32>, // @dev to avoid unnecessary calculation of cum_salary
        _last_update_month_id: u32, // @dev to avoid unnecessary calculation of cum_salary
        _master: ContractAddress, // @dev master contract address
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SalaryPoolUpdated: SalaryPoolUpdated,
        SalaryClaimed: SalaryClaimed,
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
        amount: u256,
        recipient: ContractAddress
    }
    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner_: ContractAddress, token_: ContractAddress, master_: ContractAddress) {
        self._token.write(token_); // USDC
        // self._token.write(contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()); // USDC
        self._master.write(master_);
        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner_);

    }

    #[external(v0)]
    impl SalaryDistributor of super::ISalaryDistributor<ContractState> {
        //
        // Getters
        //
        fn token(self: @ContractState) -> ContractAddress {
            self._token.read()
        }

        fn master(self: @ContractState) -> ContractAddress {
            self._master.read()
        }

        fn get_cum_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            InternalImpl::_calculate_cum_salary(self, contributor)
        }

        fn get_claimed_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            self._salary.read(contributor).claimed_salary
        }
        // for debugging will remove after review
        // fn get_cum_salarys(self: @ContractState, contributor: ContractAddress){
        //     InternalImpl::get_guild_cum_salarys(self, contributor, 'dev');
        //     InternalImpl::get_guild_cum_salarys(self, contributor, 'design');
        //     InternalImpl::get_guild_cum_salarys(self, contributor, 'problem_solving');
        //     InternalImpl::get_guild_cum_salarys(self, contributor, 'marcom');
        //     InternalImpl::get_guild_cum_salarys(self, contributor, 'research');
        // }

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

        fn update_cum_salary(ref self: ContractState, contributor: ContractAddress) {
            let last_update_month_id_contributor = self._last_update_month_id_contributor.read(contributor);
            let last_update_month_id = self._last_update_month_id.read();
            if (last_update_month_id_contributor == last_update_month_id) {
                return; // cum_salary already up to date
            }

            let cum_salary = InternalImpl::_calculate_cum_salary(@self, contributor);
            let old_salary = self._salary.read(contributor);
            self._salary.write(contributor, Salary{cum_salary: cum_salary, claimed_salary: old_salary.claimed_salary });
            self._last_update_month_id_contributor.write(contributor, last_update_month_id);
        }

        fn claim_salary(ref self: ContractState, recipient: ContractAddress) {
            let contributor = get_caller_address();
            self.update_cum_salary(contributor);
            let salary = self._salary.read(contributor);
            let claimable_amount = salary.cum_salary - salary.claimed_salary;
            assert(claimable_amount > 0, 'ZERO_CLAIMABLE_AMOUNT');

            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            // update claimed salary
            self._salary.write(contributor, Salary{cum_salary: salary.cum_salary, claimed_salary: salary.claimed_salary + claimable_amount});
            tokenDispatcher.transfer(recipient, claimable_amount);
            self.emit(SalaryClaimed{amount: claimable_amount, recipient: recipient});

        }

        

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _calculate_cum_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            let mut cum_salary = 0_u256;
            cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, 'dev');
            cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, 'design');
            cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, 'problem_solving');
            cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, 'marcom');
            cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, 'research');

            cum_salary
        }

        fn _calculate_guild_cum_salary(self: @ContractState, contributor: ContractAddress, guild: felt252) -> u256 {
            let master = self._master.read();
            let masterDispatcher = IMasterDispatcher { contract_address: master };
            let contribution_data = masterDispatcher.get_contributions_data(contributor, guild);

            let mut cum_salary = 0_u256;
            let mut cum_salarys: Array<u256> = ArrayTrait::new();

            let mut current_index = 0_u32;
            loop {
                if (current_index == contribution_data.len()) {
                    break;
                }

                let pool_amount = self._salary_pool.read((*contribution_data[current_index], guild));
                let total_contribution: u256 = masterDispatcher.get_guild_total_contribution(*contribution_data[current_index], guild).into();
                let contributor_point_earned: u256 = (*contribution_data[current_index + 1]).into();
                cum_salary += (pool_amount * contributor_point_earned) / total_contribution;
                cum_salarys.append((pool_amount * contributor_point_earned) / total_contribution);
                current_index += 2;

            };
            cum_salary
        }

        // for debugging will remove after review
        // fn get_guild_cum_salarys(self: @ContractState, contributor: ContractAddress, guild: felt252){
        //     let master = self._master.read();
        //     let masterDispatcher = IMasterDispatcher { contract_address: master };
        //     let contribution_data = masterDispatcher.get_contributions_data(contributor, guild);

        //     let mut cum_salary = 0_u256;
        //     let mut cum_salarys: Array<felt252> = ArrayTrait::new();

        //     let mut current_index = 0_u32;
        //     loop {
        //         if (current_index == contribution_data.len()) {
        //             break;
        //         }

        //         let pool_amount = self._salary_pool.read((*contribution_data[current_index], guild));
        //         let total_contribution: u256 = masterDispatcher.get_guild_total_contribution(*contribution_data[current_index], guild).into();
        //         let contributor_point_earned: u256 = (*contribution_data[current_index + 1]).into();
        //         cum_salary += (pool_amount * contributor_point_earned) / total_contribution;
        //         cum_salarys.append(((pool_amount * contributor_point_earned) / total_contribution).try_into().unwrap());
        //         cum_salarys.append((pool_amount).try_into().unwrap());
        //         cum_salarys.append((total_contribution).try_into().unwrap());
        //         cum_salarys.append((contributor_point_earned).try_into().unwrap());
        //         current_index += 2;

        //     };
        //     cum_salarys.len().print();
        //     cum_salarys.clone().print();
            
        // }


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