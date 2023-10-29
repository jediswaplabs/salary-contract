use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait, ContractClass, start_warp, start_prank, stop_prank,
                   spy_events, SpyOn, EventSpy, EventFetcher, Event, EventAssertions };
use tests::utils::{ deployer_addr, user1, user2, user3, USDC, TOKEN_MULTIPLIER};
use salary::utils::master::MonthlyContribution;
use salary::utils::master::Contribution;
use integer::u256_from_felt252;



#[starknet::interface]
trait IERC20<TContractState> {
    // view functions
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    // external functions
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::interface]
trait ISalary<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn token(self: @TContractState) -> ContractAddress;
    fn get_cum_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    fn get_claimed_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    fn get_cum_salarys(self: @TContractState, contributor: ContractAddress);

    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<felt252>);
    fn claim_salary(ref self: TContractState, recipient: ContractAddress);
}

#[starknet::interface]
trait IMaster<TContractState> {
    fn get_last_update_id(self: @TContractState) -> u32;
    fn get_contributions_points(self: @TContractState, contributor: ContractAddress) -> Contribution;

    fn update_contibutions(ref self: TContractState,  month_id: u32, contributions: Array::<MonthlyContribution>);
    fn migrate_points_initiated_by_DAO(ref self: TContractState, old_addresses: Array::<ContractAddress>, new_addresses: Array::<ContractAddress> );
    fn initialise(ref self: TContractState, dev_guild: ContractAddress, design_guild: ContractAddress, marcom_guild: ContractAddress, problem_solver_guild: ContractAddress, research_guild: ContractAddress);
    fn migrate_points_initiated_by_holder(ref self: TContractState, new_address: ContractAddress);
    fn execute_migrate_points_initiated_by_holder(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);

}

fn deploy_mockUSDC(initial_supply: u256) -> ContractAddress {
    let erc20_class = declare('ERC20');
    let name = 'mock USDC';
    let symbol = 'mUSDC';
    let mut usdc_constructor_calldata = Default::default();
    Serde::serialize(@name, ref usdc_constructor_calldata);
    Serde::serialize(@symbol, ref usdc_constructor_calldata);
    Serde::serialize(@initial_supply, ref usdc_constructor_calldata);
    Serde::serialize(@deployer_addr(), ref usdc_constructor_calldata);
    let usdc_address = erc20_class.deploy(@usdc_constructor_calldata).unwrap();

    usdc_address
}

// Deploying salary and master contract
fn deploy_contracts(usdc: ContractAddress) -> (ContractAddress, ContractAddress)  {
    let mut master_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref master_constructor_calldata);
    let master_class = declare('Master');
    let master_address = master_class.deploy(@master_constructor_calldata).unwrap();

    let mut salary_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref salary_constructor_calldata);
    Serde::serialize(@usdc, ref salary_constructor_calldata);
    Serde::serialize(@master_address, ref salary_constructor_calldata);
    let salary_class = declare('SalaryDistributor');
    let salary_address = salary_class.deploy(@salary_constructor_calldata).unwrap();


    (master_address, salary_address)
}

fn update_contributions(master_address: ContractAddress) -> (MonthlyContribution, MonthlyContribution, MonthlyContribution, MonthlyContribution) {
    let master_dispatcher = IMasterDispatcher { contract_address: master_address };

    let user1_contribution_sept = MonthlyContribution{ contributor: user1(), dev: 120, design: 250, problem_solving: 30, marcom: 20, research: 10};
    // let user1_contribution_sept = MonthlyContribution{ contributor: user1(), dev: 120, design: 0, marcom: 0, problem_solving: 0, research: 0};
    let user2_contribution_sept = MonthlyContribution{ contributor: user2(), dev: 200, design: 150, problem_solving: 0, marcom: 100, research: 70};

    let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    contributions.append(user1_contribution_sept);
    contributions.append(user2_contribution_sept);

    // updating contribution for Sept 2023
    start_prank(master_address, deployer_addr());
    master_dispatcher.update_contibutions(092023, contributions);
    stop_prank(master_address);

    let user1_contribution_oct = MonthlyContribution{ contributor: user1(), dev: 150, design: 20,  problem_solving: 45, marcom: 0, research: 35};
    // let user1_contribution_oct = MonthlyContribution{ contributor: user1(), dev: 150, design: 0, marcom: 0, problem_solving: 0, research: 0};
    let user2_contribution_oct = MonthlyContribution{ contributor: user2(), dev: 100, design: 0, problem_solving: 55, marcom: 50, research: 90};

    let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    contributions.append(user1_contribution_oct);
    contributions.append(user2_contribution_oct);

    // updating contribution for Oct 2023
    start_prank(master_address, deployer_addr());
    master_dispatcher.update_contibutions(102023, contributions);
    stop_prank(master_address);

    (user1_contribution_sept, user2_contribution_sept, user1_contribution_oct, user2_contribution_oct)
}

#[test]
fn test_add_fund_and_claim() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);
    let (user1_contribution_sept, user2_contribution_sept, user1_contribution_oct, user2_contribution_oct) = update_contributions(master_address);

    let master_dispatcher = IMasterDispatcher { contract_address: master_address };
    let salary_dispatcher = ISalaryDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let safe_salary_dispatcher = ISalarySafeDispatcher { contract_address: salary_address };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append('dev');
    guilds.append('design');
    guilds.append('problem_solving');
    guilds.append('marcom');
    guilds.append('research');

    let mut amounts1: Array<u256> = ArrayTrait::new();
    amounts1.append(10 * TOKEN_MULTIPLIER);
    amounts1.append(20 * TOKEN_MULTIPLIER);
    amounts1.append(30 * TOKEN_MULTIPLIER);
    amounts1.append(40 * TOKEN_MULTIPLIER);
    amounts1.append(50 * TOKEN_MULTIPLIER);

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(50 * TOKEN_MULTIPLIER);
    amounts2.append(40 * TOKEN_MULTIPLIER);
    amounts2.append(30 * TOKEN_MULTIPLIER);
    amounts2.append(20 * TOKEN_MULTIPLIER);
    amounts2.append(10 * TOKEN_MULTIPLIER);
   

    start_prank(usdc, deployer_addr());
    usdc_dispatcher.approve(salary_address, 300 * TOKEN_MULTIPLIER);
    stop_prank(usdc);

    start_prank(salary_address, deployer_addr());
    salary_dispatcher.add_fund_to_salary_pools(092023, amounts1, guilds.clone());
    salary_dispatcher.add_fund_to_salary_pools(102023, amounts2, guilds.clone());
    stop_prank(salary_address);

    // verifying balance of contract 
    let contract_balance = usdc_dispatcher.balance_of(salary_address);
    assert(contract_balance == 300 * TOKEN_MULTIPLIER, 'incorrect balance');

    let user1_expected_cum_salary = (120 * 10 * TOKEN_MULTIPLIER / 320) + (150 * 50 * TOKEN_MULTIPLIER / 250) + 
                                    (250 * 20 * TOKEN_MULTIPLIER / 400) + (20 * 40 * TOKEN_MULTIPLIER / 20) +
                                    (30 * 30 * TOKEN_MULTIPLIER / 30) + (45 * 30 * TOKEN_MULTIPLIER / 100) +
                                    (20 * 40 * TOKEN_MULTIPLIER / 120) + (0 * 20 * TOKEN_MULTIPLIER / 50) +
                                    (10 * 50 * TOKEN_MULTIPLIER / 80) + (35 * 10 * TOKEN_MULTIPLIER / 125);

    let user2_expected_cum_salary = (200 * 10 * TOKEN_MULTIPLIER / 320) + (100 * 50 * TOKEN_MULTIPLIER / 250) + 
                                    (150 * 20 * TOKEN_MULTIPLIER / 400) + (0 * 40 * TOKEN_MULTIPLIER / 20) +
                                    (0 * 30 * TOKEN_MULTIPLIER / 30) + (55 * 30 * TOKEN_MULTIPLIER / 100) +
                                    (100 * 40 * TOKEN_MULTIPLIER / 120) + (50 * 20 * TOKEN_MULTIPLIER / 50) +
                                    (70 * 50 * TOKEN_MULTIPLIER / 80) + (90 * 10 * TOKEN_MULTIPLIER / 125);
    


    
    let user1_cum_salary = salary_dispatcher.get_cum_salary(user1());
    assert(user1_cum_salary == user1_expected_cum_salary,'incorrect user1 cum salary');

    let user2_cum_salary = salary_dispatcher.get_cum_salary(user2());
    assert(user2_cum_salary == user2_expected_cum_salary,'incorrect user2 cum salary');

    // claiming the salary
    start_prank(salary_address, user1());
    salary_dispatcher.claim_salary(user1());
    stop_prank(salary_address);

    // verfying tokens transfered successful
    let user1_balance = usdc_dispatcher.balance_of(user1());
    assert(user1_balance == user1_expected_cum_salary, 'incorrect user1 balance');

    // verifying claimed_salary is updated
    let user1_claimed_salary = salary_dispatcher.get_claimed_salary(user1());
    assert(user1_claimed_salary == user1_expected_cum_salary, 'incorrect claimed amount');

    // claiming the salary to differnt account
    start_prank(salary_address, user2());
    salary_dispatcher.claim_salary(user3());
    stop_prank(salary_address);

    // verfying tokens transfered successful
    let user3_balance = usdc_dispatcher.balance_of(user3());
    assert(user3_balance == user2_expected_cum_salary, 'incorrect user3 balance');

    // verifying claimed_salary is updated
    let user2_claimed_salary = salary_dispatcher.get_claimed_salary(user2());
    assert(user2_claimed_salary == user2_expected_cum_salary, 'incorrect claimed amount');


    // claiming for the second time
    start_prank(salary_address, user1());
    match safe_salary_dispatcher.claim_salary(user1()) {
        Result::Ok(_) => panic_with_felt252('shouldve panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'ZERO_CLAIMABLE_AMOUNT', *panic_data.at(0));
        }
    };
    stop_prank(salary_address);
}