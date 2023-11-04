use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait, ContractClass, start_warp, start_prank, stop_prank,
                   spy_events, SpyOn, EventSpy, EventFetcher, Event, EventAssertions };
use tests::utils::{ deployer_addr, user1, user2, user3, USDC, TOKEN_MULTIPLIER, URI};
use salary::utils::master::MonthlyContribution;
use salary::utils::master::Contribution;
use integer::u256_from_felt252;
// use snforge_std::PrintTrait;


const TIER_MULTIPLIER: u256 = 1000;

#[starknet::interface]
trait IERC20<TContractState> {
    // view functions
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    // external functions
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait ISalary2<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn token(self: @TContractState) -> ContractAddress;
    fn guild_contract(self: @TContractState, guild: felt252) -> ContractAddress;
    fn get_total_effective_points(self: @TContractState, month_id: u32, guild: felt252) -> u32;
    fn get_claimable_salary(self: @TContractState, contributor: ContractAddress, month_ids: Array<u32>) -> u256;
    fn get_claimed_salary(self: @TContractState, contributor: ContractAddress) -> u256;

    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<felt252>);
    fn process_salary(ref self: TContractState, month_id: u32, guild: felt252, contributors: Array<ContractAddress>);
    fn claim_salary(ref self: TContractState, recipient: ContractAddress, month_ids: Array<u32>);
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

fn deploy_master() -> ContractAddress {
    let mut master_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref master_constructor_calldata);
    let master_class = declare('Master');
    let master_address = master_class.deploy(@master_constructor_calldata).unwrap();

    master_address
}



fn deploy_guild(name: felt252, symbol: felt252, master_address: ContractAddress, guild_class: snforge_std::cheatcodes::contract_class::ContractClass) -> ContractAddress {

    let mut contribution_levels: Array<u32> = ArrayTrait::new();
    contribution_levels.append(100);
    contribution_levels.append(200);
    contribution_levels.append(500);
    contribution_levels.append(1000);

    let mut guild_constructor_calldata = Default::default();
    Serde::serialize(@name, ref guild_constructor_calldata);
    Serde::serialize(@symbol, ref guild_constructor_calldata);
    Serde::serialize(@URI(), ref guild_constructor_calldata);
    Serde::serialize(@deployer_addr(), ref guild_constructor_calldata);
    Serde::serialize(@master_address, ref guild_constructor_calldata);
    Serde::serialize(@contribution_levels, ref guild_constructor_calldata);

    let guild_address = guild_class.deploy(@guild_constructor_calldata).unwrap();

    guild_address
}

// Deploying salary contract
fn deploy_contracts() -> (ContractAddress, ContractAddress, ContractAddress) {
    let initial_supply: u256 = 1000 * TOKEN_MULTIPLIER;
    let usdc = deploy_mockUSDC(initial_supply);
    let master_address = deploy_master();

    let dev_guild_address = deploy_guild('Jedi Dev Guild SBT', 'JEDI-DEV', master_address, declare('DevGuildSBT'));
    let design_guild_address = deploy_guild('Jedi Dev Guild SBT', 'JEDI-DEV', master_address, declare('DesignGuildSBT'));
    let problem_solving_guild_address = deploy_guild('Jedi Dev Guild SBT', 'JEDI-DEV', master_address, declare('ProblemSolvingGuildSBT'));
    let marcom_guild_address = deploy_guild('Jedi Dev Guild SBT', 'JEDI-DEV', master_address, declare('MarcomGuildSBT'));
    let research_guild_address = deploy_guild('Jedi Dev Guild SBT', 'JEDI-DEV', master_address, declare('ResearchGuildSBT'));

    let mut guilds: Array<ContractAddress> = ArrayTrait::new();
    guilds.append(dev_guild_address);
    guilds.append(design_guild_address);
    guilds.append(problem_solving_guild_address);
    guilds.append(marcom_guild_address);
    guilds.append(research_guild_address);

    let mut salary_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref salary_constructor_calldata);
    Serde::serialize(@usdc, ref salary_constructor_calldata);
    Serde::serialize(@master_address, ref salary_constructor_calldata);
    Serde::serialize(@guilds, ref salary_constructor_calldata);
    let salary_class = declare('SalaryDistributor2');
    let salary_address = salary_class.deploy(@salary_constructor_calldata).unwrap();


    (usdc, master_address, salary_address)
}

fn update_contributions_sept(master_address: ContractAddress) {
    let master_dispatcher = IMasterDispatcher { contract_address: master_address };

    let user1_contribution_sept = MonthlyContribution{ contributor: user1(), dev: 120, design: 500, problem_solving: 30, marcom: 0, research: 10};
    // let user1_contribution_sept = MonthlyContribution{ contributor: user1(), dev: 120, design: 0, marcom: 0, problem_solving: 0, research: 0};
    let user2_contribution_sept = MonthlyContribution{ contributor: user2(), dev: 200, design: 150, problem_solving: 0, marcom: 100, research: 70};

    let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    contributions.append(user1_contribution_sept);
    contributions.append(user2_contribution_sept);

    // updating contribution for Sept 2023
    start_prank(master_address, deployer_addr());
    master_dispatcher.update_contibutions(092023, contributions);
    stop_prank(master_address);

    // let user1_contribution_oct = MonthlyContribution{ contributor: user1(), dev: 150, design: 20,  problem_solving: 45, marcom: 0, research: 35};
    // // let user1_contribution_oct = MonthlyContribution{ contributor: user1(), dev: 150, design: 0, marcom: 0, problem_solving: 0, research: 0};
    // let user2_contribution_oct = MonthlyContribution{ contributor: user2(), dev: 100, design: 0, problem_solving: 55, marcom: 50, research: 90};

    // let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    // contributions.append(user1_contribution_oct);
    // contributions.append(user2_contribution_oct);

    // // updating contribution for Oct 2023
    // start_prank(master_address, deployer_addr());
    // master_dispatcher.update_contibutions(102023, contributions);
    // stop_prank(master_address);
}

fn update_contributions_oct(master_address: ContractAddress) {
    let master_dispatcher = IMasterDispatcher { contract_address: master_address };

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
    
    let (usdc, _, salary_address) = deploy_contracts();

    let salary_dispatcher = ISalary2Dispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append('dev');
    guilds.append('design');
    guilds.append('problem_solving');
    guilds.append('marcom');
    guilds.append('research');

    let mut amounts: Array<u256> = ArrayTrait::new();
    amounts.append(10 * TOKEN_MULTIPLIER);
    amounts.append(20 * TOKEN_MULTIPLIER);
    amounts.append(30 * TOKEN_MULTIPLIER);
    amounts.append(40 * TOKEN_MULTIPLIER);
    amounts.append(50 * TOKEN_MULTIPLIER);

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

    // defining variables to check in events emitted
    let dev_guild = 'dev';
    let dev_fund = 10 * TOKEN_MULTIPLIER;
    let design_guild = 'design';
    let design_fund = 20 * TOKEN_MULTIPLIER;
    let problem_solving_guild = 'problem_solving';
    let problem_solving_fund = 30 * TOKEN_MULTIPLIER;
    let marcom_guild = 'marcom';
    let marcom_fund = 40 * TOKEN_MULTIPLIER;
    let research_guild = 'research';
    let research_fund = 50 * TOKEN_MULTIPLIER;

    let mut event_data_dev = Default::default();
    Serde::serialize(@month_id, ref event_data_dev);
    Serde::serialize(@dev_guild, ref event_data_dev);
    Serde::serialize(@dev_fund, ref event_data_dev);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_dev }
    ]);

    let mut event_data_design = Default::default();
    Serde::serialize(@month_id, ref event_data_design);
    Serde::serialize(@design_guild, ref event_data_design);
    Serde::serialize(@design_fund, ref event_data_design);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_design }
    ]);

    let mut event_data_problem_solving = Default::default();
    Serde::serialize(@month_id, ref event_data_problem_solving);
    Serde::serialize(@problem_solving_guild, ref event_data_problem_solving);
    Serde::serialize(@problem_solving_fund, ref event_data_problem_solving);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_problem_solving }
    ]);

    let mut event_data_marcom = Default::default();
    Serde::serialize(@month_id, ref event_data_marcom);
    Serde::serialize(@marcom_guild, ref event_data_marcom);
    Serde::serialize(@marcom_fund, ref event_data_marcom);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_marcom }
    ]);

    let mut event_data_research = Default::default();
    Serde::serialize(@month_id, ref event_data_research);
    Serde::serialize(@research_guild, ref event_data_research);
    Serde::serialize(@research_fund, ref event_data_research);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryPoolUpdated', keys: array![], data: event_data_research }
    ]);

}

#[test]
fn test_add_fund_same_month_new_guild() { 
    let (usdc, _, salary_address) = deploy_contracts();

    let salary_dispatcher = ISalary2Dispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let mut guilds: Array<felt252> = ArrayTrait::new();
    guilds.append('dev');
    guilds.append('design');
    guilds.append('problem_solving');
    guilds.append('marcom');

    let mut amounts1: Array<u256> = ArrayTrait::new();
    amounts1.append(10 * TOKEN_MULTIPLIER);
    amounts1.append(20 * TOKEN_MULTIPLIER);
    amounts1.append(30 * TOKEN_MULTIPLIER);
    amounts1.append(40 * TOKEN_MULTIPLIER);


    let mut guilds2: Array<felt252> = ArrayTrait::new();
    guilds2.append('research');

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(50 * TOKEN_MULTIPLIER);

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
    let (usdc, _, salary_address) = deploy_contracts();

    let safe_salary_dispatcher = ISalary2SafeDispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

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

    let mut guilds2: Array<felt252> = ArrayTrait::new();
    guilds2.append('research');

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
fn test_process_salary_and_claim() { 
    let (usdc, master_address, salary_address) = deploy_contracts();

    update_contributions_sept(master_address);

    let master_dispatcher = IMasterDispatcher { contract_address: master_address };
    let salary_dispatcher = ISalary2Dispatcher { contract_address: salary_address };
    let usdc_dispatcher = IERC20Dispatcher { contract_address: usdc };

    let safe_salary_dispatcher = ISalary2SafeDispatcher { contract_address: salary_address };

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

    start_prank(usdc, deployer_addr());
    usdc_dispatcher.approve(salary_address, 300 * TOKEN_MULTIPLIER);
    stop_prank(usdc);

    start_prank(salary_address, deployer_addr());
    salary_dispatcher.add_fund_to_salary_pools(092023, amounts1, guilds.clone());
    // salary_dispatcher.add_fund_to_salary_pools(102023, amounts2, guilds.clone());
    stop_prank(salary_address);

    let mut contributors1: Array<ContractAddress> = ArrayTrait::new();
    contributors1.append(user1());
    contributors1.append(user2());

    // processing salary for sept
    start_prank(salary_address, deployer_addr());
    salary_dispatcher.process_salary(092023, 'dev', contributors1.clone() );
    salary_dispatcher.process_salary(092023, 'design', contributors1.clone() );
    salary_dispatcher.process_salary(092023, 'problem_solving', contributors1.clone() );
    salary_dispatcher.process_salary(092023, 'marcom', contributors1.clone() );
    salary_dispatcher.process_salary(092023, 'research', contributors1.clone() );
    stop_prank(salary_address);

    let total_effective_points_dev_sept_expected = (120 * 1000) / TIER_MULTIPLIER + (200 * 1200) / TIER_MULTIPLIER;
    let total_effective_points_dev_sept: u256 = salary_dispatcher.get_total_effective_points(092023, 'dev').into();
    assert(total_effective_points_dev_sept_expected == total_effective_points_dev_sept, 'incorrect value1');

    let total_effective_points_design_sept_expected = (500 * 1350) / TIER_MULTIPLIER + (150 * 1000) / TIER_MULTIPLIER;
    let total_effective_points_design_sept: u256 = salary_dispatcher.get_total_effective_points(092023, 'design').into();
    assert(total_effective_points_design_sept_expected == total_effective_points_design_sept, 'incorrect value2');

    let total_effective_points_problem_solving_sept_expected = (30 * 0) / TIER_MULTIPLIER + (0 * 0) / TIER_MULTIPLIER;
    let total_effective_points_problem_solving_sept: u256 = salary_dispatcher.get_total_effective_points(092023, 'problem_solving').into();
    assert(total_effective_points_problem_solving_sept_expected == total_effective_points_problem_solving_sept, 'incorrect value3');

    let total_effective_points_marcom_sept_expected = (0 * 0) / TIER_MULTIPLIER + (100 * 1000) / TIER_MULTIPLIER;
    let total_effective_points_marcom_sept: u256 = salary_dispatcher.get_total_effective_points(092023, 'marcom').into();
    assert(total_effective_points_marcom_sept_expected == total_effective_points_marcom_sept, 'incorrect value4');

    let total_effective_points_research_sept_expected = (10 * 0) / TIER_MULTIPLIER + (70 * 0) / TIER_MULTIPLIER;
    let total_effective_points_research_sept: u256 = salary_dispatcher.get_total_effective_points(092023, 'research').into();
    assert(total_effective_points_research_sept_expected == total_effective_points_research_sept, 'incorrect value5');


    let user1_expected_salary_sept = (120 * 1000 * 10 * TOKEN_MULTIPLIER) / (total_effective_points_dev_sept * TIER_MULTIPLIER) +
                                    (500 * 1350 * 20 * TOKEN_MULTIPLIER) / (total_effective_points_design_sept * TIER_MULTIPLIER)+
                                    // (30 * 0 * 30 * TOKEN_MULTIPLIER) / (total_effective_points_problem_solving_sept * TIER_MULTIPLIER)+ // commenting this expression as total effective point = 0
                                    (0 * 0 * 40 * TOKEN_MULTIPLIER) / (total_effective_points_marcom_sept * TIER_MULTIPLIER);
                                    // (10 * 0 * 50 * TOKEN_MULTIPLIER) / (total_effective_points_research_sept * TIER_MULTIPLIER);  


    let user2_expected_salary_sept = (200 * 1200 * 10 * TOKEN_MULTIPLIER) / (total_effective_points_dev_sept * TIER_MULTIPLIER) +
                                    (150 * 1000 * 20 * TOKEN_MULTIPLIER) / (total_effective_points_design_sept * TIER_MULTIPLIER)+
                                    // (0 * 0 * 30 * TOKEN_MULTIPLIER) / (total_effective_points_problem_solving_sept * TIER_MULTIPLIER)+ // commenting this expression as total effective point = 0
                                    (100 * 1000 * 40 * TOKEN_MULTIPLIER) / (total_effective_points_marcom_sept * TIER_MULTIPLIER);
                                    // (10 * 0 * 50 * TOKEN_MULTIPLIER) / (total_effective_points_research_sept * TIER_MULTIPLIER);  
    
    let mut month_ids: Array<u32> = ArrayTrait::new();
    month_ids.append(092023);
    // month_ids.append(102023);

    let mut user1_claimable_salary = salary_dispatcher.get_claimable_salary(user1(), month_ids.clone());
    assert(user1_claimable_salary == user1_expected_salary_sept,'incorrect user1 salary');
    let mut user2_claimable_salary = salary_dispatcher.get_claimable_salary(user2(), month_ids.clone());
    assert(user2_claimable_salary == user2_expected_salary_sept,'incorrect user2 salary');


    // Updating contribution for October
    update_contributions_oct(master_address);

    let mut amounts2: Array<u256> = ArrayTrait::new();
    amounts2.append(50 * TOKEN_MULTIPLIER);
    amounts2.append(40 * TOKEN_MULTIPLIER);
    amounts2.append(30 * TOKEN_MULTIPLIER);
    amounts2.append(20 * TOKEN_MULTIPLIER);
    amounts2.append(10 * TOKEN_MULTIPLIER);

    start_prank(salary_address, deployer_addr());
    salary_dispatcher.add_fund_to_salary_pools(102023, amounts2, guilds.clone());
    stop_prank(salary_address);

    // processing salary for oct
    start_prank(salary_address, deployer_addr());
    salary_dispatcher.process_salary(102023, 'dev', contributors1.clone() );
    salary_dispatcher.process_salary(102023, 'design', contributors1.clone() );
    salary_dispatcher.process_salary(102023, 'problem_solving', contributors1.clone() );
    salary_dispatcher.process_salary(102023, 'marcom', contributors1.clone() );
    salary_dispatcher.process_salary(102023, 'research', contributors1.clone() );
    stop_prank(salary_address);

    let total_effective_points_dev_oct_expected = (150 * 1200) / TIER_MULTIPLIER + (100 * 1200) / TIER_MULTIPLIER;
    let total_effective_points_design_oct_expected = (20 * 1350) / TIER_MULTIPLIER + (0 * 1000) / TIER_MULTIPLIER;
    let total_effective_points_problem_solving_oct_expected = (45 * 0) / TIER_MULTIPLIER + (55 * 0) / TIER_MULTIPLIER;
    let total_effective_points_marcom_oct_expected = (0 * 0) / TIER_MULTIPLIER + (50 * 1000) / TIER_MULTIPLIER;
    let total_effective_points_research_oct_expected = (35 * 0) / TIER_MULTIPLIER + (90 * 1000) / TIER_MULTIPLIER;

    let user1_expected_salary_oct = (150 * 1200 * 50 * TOKEN_MULTIPLIER) / (total_effective_points_dev_oct_expected * TIER_MULTIPLIER) +
                                    (20 * 1350 * 40 * TOKEN_MULTIPLIER) / (total_effective_points_design_oct_expected * TIER_MULTIPLIER)+
                                    // (45 * 0 * 30 * TOKEN_MULTIPLIER) / (total_effective_points_problem_solving_oct_expected * TIER_MULTIPLIER)+ // commenting this expression as total effective point = 0
                                    (0 * 0 * 20 * TOKEN_MULTIPLIER) / (total_effective_points_marcom_oct_expected * TIER_MULTIPLIER) +
                                    (35 * 0 * 10 * TOKEN_MULTIPLIER) / (total_effective_points_research_oct_expected * TIER_MULTIPLIER);  


    let user2_expected_salary_oct = (100 * 1200 * 50 * TOKEN_MULTIPLIER) / (total_effective_points_dev_oct_expected * TIER_MULTIPLIER) +
                                    (0 * 1000 * 40 * TOKEN_MULTIPLIER) / (total_effective_points_design_oct_expected * TIER_MULTIPLIER)+
                                    // (55 * 0 * 30 * TOKEN_MULTIPLIER) / (total_effective_points_problem_solving_oct_expected * TIER_MULTIPLIER)+ // commenting this expression as total effective point = 0
                                    (50 * 1000 * 20 * TOKEN_MULTIPLIER) / (total_effective_points_marcom_oct_expected * TIER_MULTIPLIER) +
                                    (90 * 1000 * 10 * TOKEN_MULTIPLIER) / (total_effective_points_research_oct_expected * TIER_MULTIPLIER);  
    
    
    month_ids.append(102023);

    user1_claimable_salary = salary_dispatcher.get_claimable_salary(user1(), month_ids.clone());
    assert(user1_claimable_salary == user1_expected_salary_sept + user1_expected_salary_oct,'incorrect user1 salarya');

    user2_claimable_salary = salary_dispatcher.get_claimable_salary(user2(), month_ids.clone());
    assert(user2_claimable_salary == user2_expected_salary_sept + user2_expected_salary_oct,'incorrect user2 salarya');

    // testing claim
    let mut spy = spy_events(SpyOn::One(salary_address));
    start_prank(salary_address, user1());
    salary_dispatcher.claim_salary(user1(), month_ids.clone());
    stop_prank(salary_address);

    let mut event_data1 = Default::default();
    let mut month_id = *month_ids[0];
    Serde::serialize(@month_id, ref event_data1);
    Serde::serialize(@user1_expected_salary_sept, ref event_data1);
    Serde::serialize(@user1(), ref event_data1);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data1 }
    ]);

    let mut event_data2 = Default::default();
    month_id = *month_ids[1];
    Serde::serialize(@month_id, ref event_data2);
    Serde::serialize(@user1_expected_salary_oct, ref event_data2);
    Serde::serialize(@user1(), ref event_data2);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data2 }
    ]);


    // verfying tokens transfered successful
    let user1_balance = usdc_dispatcher.balance_of(user1());
    assert(user1_balance == user1_claimable_salary, 'incorrect user1 balance');

    // verifying claimed_salary and claimable salary is updated
    let user1_claimed_salary = salary_dispatcher.get_claimed_salary(user1());
    assert(user1_claimed_salary == user1_claimable_salary, 'incorrect claimed amount');
    let user1_claimable_salary_new = salary_dispatcher.get_claimable_salary(user1(), month_ids.clone());
    assert(user1_claimable_salary_new == 0, 'incorrect claimable salary');

    // testing partial claim
    let mut month_ids_only_sept: Array<u32> = ArrayTrait::new();
    month_ids_only_sept.append(092023);

    let mut month_ids_only_oct: Array<u32> = ArrayTrait::new();
    month_ids_only_oct.append(102023);
    
    let mut spy = spy_events(SpyOn::One(salary_address));
    // claiming the salary to differnt account
    start_prank(salary_address, user2());
    salary_dispatcher.claim_salary(user3(), month_ids_only_sept.clone());
    stop_prank(salary_address);

    let mut event_data3 = Default::default();
    month_id = *month_ids_only_sept[0];
    Serde::serialize(@month_id, ref event_data3);
    Serde::serialize(@user2_expected_salary_sept, ref event_data3);
    Serde::serialize(@user3(), ref event_data3);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data3 }
    ]);

    // verfying tokens transfered successful
    let user3_balance = usdc_dispatcher.balance_of(user3());
    assert(user3_balance == user2_expected_salary_sept, 'incorrect user3 balance');

    // verifying claimed_salary claimable salary is updated
    let user2_claimed_salary = salary_dispatcher.get_claimed_salary(user2());
    assert(user2_claimed_salary == user2_expected_salary_sept, 'incorrect claimed amount');
    let user2_claimable_salary_new = salary_dispatcher.get_claimable_salary(user2(), month_ids.clone());
    assert(user2_claimable_salary_new == user2_expected_salary_oct, 'incorrect claimable salary');

    // claimimg remaining salary (For oct)
    start_prank(salary_address, user2());
    salary_dispatcher.claim_salary(user3(), month_ids_only_oct.clone());
    stop_prank(salary_address);

    let mut event_data4 = Default::default();
    month_id = *month_ids_only_oct[0];
    Serde::serialize(@month_id, ref event_data4);
    Serde::serialize(@user2_expected_salary_oct, ref event_data4);
    Serde::serialize(@user3(), ref event_data4);
    spy.assert_emitted(@array![
        Event { from: salary_address, name: 'SalaryClaimed', keys: array![], data: event_data4 }
    ]);

    // verfying tokens transfered successful
    let user3_balance = usdc_dispatcher.balance_of(user3());
    assert(user3_balance == user2_expected_salary_sept + user2_expected_salary_oct, 'incorrect user3 balance');

    // verifying claimed_salary claimable salary is updated
    let user2_claimed_salary = salary_dispatcher.get_claimed_salary(user2());
    assert(user2_claimed_salary == user2_expected_salary_sept + user2_expected_salary_oct, 'incorrect claimed amount');
    let user2_claimable_salary_new = salary_dispatcher.get_claimable_salary(user2(), month_ids.clone());
    assert(user2_claimable_salary_new == 0, 'incorrect claimable salary');

    // claiming for the second time (with zero claimable amount)
    start_prank(salary_address, user1());
    match safe_salary_dispatcher.claim_salary(user1(), month_ids.clone()) {
        Result::Ok(_) => panic_with_felt252('shouldve panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'ZERO_CLAIMABLE_AMOUNT', *panic_data.at(0));
        }
    };
    stop_prank(salary_address);
}