use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait, ContractClass, start_warp, start_prank, stop_prank,
                   spy_events, SpyOn, EventSpy, EventFetcher, Event, EventAssertions };
use tests::utils::{ deployer_addr, user1, user2, user3, USDC, TOKEN_MULTIPLIER};
use salary::test::master::MonthlyContribution;
use salary::test::master::Contribution;
use integer::u256_from_felt252;

const DEV_GUILD: felt252 = 'dev';
const DESIGN_GUILD: felt252 = 'design';
const PROBLEM_SOLVING_GUILD: felt252 = 'problem_solving';
const MARCOM_GUILD: felt252 = 'marcom';
const RESEARCH_GUILD: felt252 = 'research';

const dev_fund_sept: u256 = 10000000000000000000; //10 * 1000000000000000000; // 10 * TOKEN_MULTIPLIER;(Comment expression not supported)
const design_fund_sept: u256 =  20000000000000000000; //20 * TOKEN_MULTIPLIER;
const problem_solving_fund_sept: u256 = 30000000000000000000; //30 * TOKEN_MULTIPLIER;
const marcom_fund_sept: u256 = 40000000000000000000; //40 * TOKEN_MULTIPLIER;
const research_fund_sept: u256 = 50000000000000000000; //50 * TOKEN_MULTIPLIER;

const dev_fund_oct: u256 = 50000000000000000000; //50 * TOKEN_MULTIPLIER;
const design_fund_oct: u256 = 40000000000000000000; //40 * TOKEN_MULTIPLIER;
const problem_solving_fund_oct: u256 = 30000000000000000000; //30 * TOKEN_MULTIPLIER;
const marcom_fund_oct: u256 = 20000000000000000000; //20 * TOKEN_MULTIPLIER;
const research_fund_oct: u256 = 10000000000000000000; //10 * TOKEN_MULTIPLIER;



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
    fn get_pool_amount(self: @TContractState, month_id: u32, guild: felt252) -> u256;
    fn get_last_update_month_id(self: @TContractState) -> u32;

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

fn update_contributions(master_address: ContractAddress) {
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

    
}

#[test]
fn test_add_fund() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);

    let salary_dispatcher = ISalaryDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append(DEV_GUILD);
    guilds.append(DESIGN_GUILD);
    guilds.append(PROBLEM_SOLVING_GUILD);
    guilds.append(MARCOM_GUILD);
    guilds.append(RESEARCH_GUILD);

    let mut amounts: Array<u256> = ArrayTrait::new();
    amounts.append(dev_fund_sept);
    amounts.append(design_fund_sept);
    amounts.append(problem_solving_fund_sept);
    amounts.append(marcom_fund_sept);
    amounts.append(research_fund_sept);

    start_prank(usdc, deployer_addr());
    usdc_dispatcher.approve(salary_address, 150 * TOKEN_MULTIPLIER);
    stop_prank(usdc);

    let month_id = 092023;

    let mut spy = spy_events(SpyOn::One(salary_address));
    start_prank(salary_address, deployer_addr());
    salary_dispatcher.add_fund_to_salary_pools(month_id, amounts, guilds);
    stop_prank(salary_address);

    // verifying balance of contract 
    let contract_balance = usdc_dispatcher.balance_of(salary_address);
    assert(contract_balance == 150 * TOKEN_MULTIPLIER, 'incorrect balance');

    // verifying if salary pool is updated correctly.
    let dev_pool = salary_dispatcher.get_pool_amount(month_id, DEV_GUILD);
    assert(dev_pool == dev_fund_sept, 'Incorrect dev pool');

    let design_pool = salary_dispatcher.get_pool_amount(month_id, DESIGN_GUILD);
    assert(design_pool == design_fund_sept, 'Incorrect design pool');

    let problem_solving_pool = salary_dispatcher.get_pool_amount(month_id, PROBLEM_SOLVING_GUILD);
    assert(problem_solving_pool == problem_solving_fund_sept, 'Incorrect problem_solving pool');

    let marcom_pool = salary_dispatcher.get_pool_amount(month_id, MARCOM_GUILD);
    assert(marcom_pool == marcom_fund_sept, 'Incorrect marcom pool');

    let research_pool = salary_dispatcher.get_pool_amount(month_id, RESEARCH_GUILD);
    assert(research_pool == research_fund_sept, 'Incorrect research pool');

    let last_update_month_id = salary_dispatcher.get_last_update_month_id();
    assert(last_update_month_id == month_id, 'incorrect month id');


    let mut event_data_dev = Default::default();
    Serde::serialize(@month_id, ref event_data_dev);
    Serde::serialize(@DEV_GUILD, ref event_data_dev);
    Serde::serialize(@dev_fund_sept, ref event_data_dev);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_dev }
    ]);

    let mut event_data_design = Default::default();
    Serde::serialize(@month_id, ref event_data_design);
    Serde::serialize(@DESIGN_GUILD, ref event_data_design);
    Serde::serialize(@design_fund_sept, ref event_data_design);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_design }
    ]);

    let mut event_data_problem_solving = Default::default();
    Serde::serialize(@month_id, ref event_data_problem_solving);
    Serde::serialize(@PROBLEM_SOLVING_GUILD, ref event_data_problem_solving);
    Serde::serialize(@problem_solving_fund_sept, ref event_data_problem_solving);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_problem_solving }
    ]);

    let mut event_data_marcom = Default::default();
    Serde::serialize(@month_id, ref event_data_marcom);
    Serde::serialize(@MARCOM_GUILD, ref event_data_marcom);
    Serde::serialize(@marcom_fund_sept, ref event_data_marcom);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_marcom }
    ]);

    let mut event_data_research = Default::default();
    Serde::serialize(@month_id, ref event_data_research);
    Serde::serialize(@RESEARCH_GUILD, ref event_data_research);
    Serde::serialize(@research_fund_sept, ref event_data_research);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_research }
    ]);



}

#[test]
fn test_add_fund_same_month_new_guild() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);

    let salary_dispatcher = ISalaryDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append(DEV_GUILD);
    guilds.append(DESIGN_GUILD);
    guilds.append(PROBLEM_SOLVING_GUILD);
    guilds.append(MARCOM_GUILD);

    let mut amounts1: Array<u256> = ArrayTrait::new();
    amounts1.append(dev_fund_sept);
    amounts1.append(design_fund_sept);
    amounts1.append(problem_solving_fund_sept);
    amounts1.append(marcom_fund_sept);


    let mut guilds2: Array<felt252> = ArrayTrait::new();
    guilds2.append(RESEARCH_GUILD);

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(research_fund_sept);

    start_prank(usdc, deployer_addr());
    usdc_dispatcher.approve(salary_address, 150 * TOKEN_MULTIPLIER);
    stop_prank(usdc);

    let month_id = 092023;
    start_prank(salary_address, deployer_addr());
    salary_dispatcher.add_fund_to_salary_pools(month_id, amounts1, guilds);
    salary_dispatcher.add_fund_to_salary_pools(month_id, amounts2, guilds2);
    stop_prank(salary_address);

}

#[test]
fn test_add_fund_again_should_revert() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);

    let safe_salary_dispatcher = ISalarySafeDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append(DEV_GUILD);
    guilds.append(DESIGN_GUILD);
    guilds.append(PROBLEM_SOLVING_GUILD);
    guilds.append(MARCOM_GUILD);
    guilds.append(RESEARCH_GUILD);

    let mut amounts1: Array<u256> = ArrayTrait::new();
    amounts1.append(dev_fund_sept);
    amounts1.append(design_fund_sept);
    amounts1.append(problem_solving_fund_sept);
    amounts1.append(marcom_fund_sept);
    amounts1.append(research_fund_sept);

    let mut guilds2: Array<felt252> = ArrayTrait::new();
    guilds2.append(RESEARCH_GUILD);

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(40 * TOKEN_MULTIPLIER);

    start_prank(usdc, deployer_addr());
    usdc_dispatcher.approve(salary_address, 200 * TOKEN_MULTIPLIER);
    stop_prank(usdc);

    let month_id = 092023;
    start_prank(salary_address, deployer_addr());
    safe_salary_dispatcher.add_fund_to_salary_pools(month_id, amounts1, guilds);
    match safe_salary_dispatcher.add_fund_to_salary_pools(month_id, amounts2, guilds2) {
        Result::Ok(_) => panic_with_felt252('shouldve panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'ALREADY_SET', *panic_data.at(0));
        }
    };
    stop_prank(salary_address);

}

#[test]
fn test_add_fund_length_mismatch() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);

    let safe_salary_dispatcher = ISalarySafeDispatcher { contract_address: salary_address };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append(DEV_GUILD);
    guilds.append(DESIGN_GUILD);
    guilds.append(PROBLEM_SOLVING_GUILD);
    guilds.append(MARCOM_GUILD);
    guilds.append(RESEARCH_GUILD);

    let mut amounts: Array<u256> = ArrayTrait::new();
    amounts.append(dev_fund_sept);
    amounts.append(design_fund_sept);
    amounts.append(problem_solving_fund_sept);
    amounts.append(marcom_fund_sept);

    let month_id = 092023;
    start_prank(salary_address, deployer_addr());
    match safe_salary_dispatcher.add_fund_to_salary_pools(month_id, amounts, guilds) {
        Result::Ok(_) => panic_with_felt252('shouldve panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'INVALID_INPUT', *panic_data.at(0));
        }
    };
    stop_prank(salary_address);
}

#[test]
fn test_add_fund_and_claim() { 
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let (master_address, salary_address) = deploy_contracts(usdc);
    update_contributions(master_address);

    let master_dispatcher = IMasterDispatcher { contract_address: master_address };
    let salary_dispatcher = ISalaryDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let safe_salary_dispatcher = ISalarySafeDispatcher { contract_address: salary_address };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append(DEV_GUILD);
    guilds.append(DESIGN_GUILD);
    guilds.append(PROBLEM_SOLVING_GUILD);
    guilds.append(MARCOM_GUILD);
    guilds.append(RESEARCH_GUILD);

    let mut amounts1: Array<u256> = ArrayTrait::new();
    amounts1.append(dev_fund_sept);
    amounts1.append(design_fund_sept);
    amounts1.append(problem_solving_fund_sept);
    amounts1.append(marcom_fund_sept);
    amounts1.append(research_fund_sept);

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(dev_fund_oct);
    amounts2.append(design_fund_oct);
    amounts2.append(problem_solving_fund_oct);
    amounts2.append(marcom_fund_oct);
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

    let user1_expected_cum_salary = (120 * dev_fund_sept / 320) + (150 * dev_fund_oct / 250) + 
                                    (250 * design_fund_sept / 400) + (20 * design_fund_oct / 20) +
                                    (30 * problem_solving_fund_sept / 30) + (45 * problem_solving_fund_oct / 100) +
                                    (20 * marcom_fund_sept / 120) + (0 * marcom_fund_oct / 50) +
                                    (10 * research_fund_sept / 80) + (35 * research_fund_oct / 125);

    let user2_expected_cum_salary = (200 * dev_fund_sept / 320) + (100 * dev_fund_oct / 250) + 
                                    (150 * design_fund_sept / 400) + (0 * design_fund_oct / 20) +
                                    (0 * problem_solving_fund_sept / 30) + (55 * problem_solving_fund_oct / 100) +
                                    (100 * marcom_fund_sept / 120) + (50 * marcom_fund_oct / 50) +
                                    (70 * research_fund_sept / 80) + (90 * research_fund_oct / 125);
    
    
    let user1_cum_salary = salary_dispatcher.get_cum_salary(user1());
    assert(user1_cum_salary == user1_expected_cum_salary,'incorrect user1 cum salary');

    let user2_cum_salary = salary_dispatcher.get_cum_salary(user2());
    assert(user2_cum_salary == user2_expected_cum_salary,'incorrect user2 cum salary');

    let mut spy = spy_events(SpyOn::One(salary_address));
    // claiming the salary
    start_prank(salary_address, user1());
    salary_dispatcher.claim_salary(user1());
    stop_prank(salary_address);

    let mut event_data1 = Default::default();
    Serde::serialize(@user1_expected_cum_salary, ref event_data1);
    Serde::serialize(@user1(), ref event_data1);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data1 }
    ]);


    // verfying tokens transfered successful
    let user1_balance = usdc_dispatcher.balance_of(user1());
    assert(user1_balance == user1_expected_cum_salary, 'incorrect user1 balance');

    let contract_balance_after_user1_claimed = usdc_dispatcher.balance_of(salary_address);
    assert(contract_balance_after_user1_claimed == contract_balance - user1_expected_cum_salary, 'incorrect contract balance');

    // verifying claimed_salary is updated
    let user1_claimed_salary = salary_dispatcher.get_claimed_salary(user1());
    assert(user1_claimed_salary == user1_expected_cum_salary, 'incorrect claimed amount');

    let mut spy = spy_events(SpyOn::One(salary_address));
    // claiming the salary to differnt account
    start_prank(salary_address, user2());
    salary_dispatcher.claim_salary(user3());
    stop_prank(salary_address);

    let mut event_data2 = Default::default();
    Serde::serialize(@user2_expected_cum_salary, ref event_data2);
    Serde::serialize(@user3(), ref event_data2);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data2 }
    ]);

    // verfying tokens transfered successful
    let user3_balance = usdc_dispatcher.balance_of(user3());
    assert(user3_balance == user2_expected_cum_salary, 'incorrect user3 balance');

    let contract_balance_after_user2_claimed = usdc_dispatcher.balance_of(salary_address);
    assert(contract_balance_after_user2_claimed == contract_balance_after_user1_claimed - user2_expected_cum_salary, 'incorrect contract balance');

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