from itertools import count
from brownie import Wei, reverts
import brownie

def test_strategy(accounts, interface, chain, web3, history, YearnCompDaiStrategy):
    user = accounts[0]
    whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    ychad = accounts.at(web3.ens.resolve('ychad.eth'), force=True)

    solo = interface.ISoloMargin('0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e')
    comptroller = interface.ComptrollerI('0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b')
    dai = interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')
    cdai = interface.CErc20I('0x5d3a536e4d6dbd6114cc1ead35777bab948e3643')
    comp = interface.ERC20('0xc00e94cb662c3520282e6f5717214004a7f26888')
    controller = interface.IController('0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080')
    vault = interface.IVault(controller.vaults(dai))
    strategy = YearnCompDaiStrategy.deploy(controller, {'from': user})
    assert strategy.want() == vault.token() == dai
    strategy.setWithdrawalFee(0)
    strategy.setCollateralTarget('0.745 ether')
    with brownie.reverts("Target higher than collateral factor"):
        strategy.setCollateralTarget('0.75 ether')

    print('migrate strategy')
    controller.approveStrategy(dai, strategy, {'from': ychad})
    controller.setStrategy(dai, strategy, {'from': ychad})
    vault.setMin(10000, {'from': ychad})
    assert controller.strategies(dai) == strategy
    print('dai in vault:', dai.balanceOf(vault).to('ether'))

    print('deposit funds into new strategy')
    vault.earn({'from': user})
    print('balance of strategy:', strategy.balanceOf().to('ether'))

    amount = Wei('1000 ether')
    user_before = dai.balanceOf(whale)
    dai.approve(vault, amount, {'from': whale})
    print('deposit amount:', amount.to('ether'))
    vault.deposit(amount, {'from': whale})
    for i in count(1):
        print(f'\ndeposit {i}')
        vault.deposit(0, {'from': whale})
        vault.earn({'from': user})
        print('balance of strategy:', strategy.balanceOf().to('ether'))
        deposits, borrows = strategy.getCurrentPosition()
        print('deposits:', Wei(deposits).to('ether'))
        print('borrows:', Wei(borrows).to('ether'))
        collat = borrows / deposits
        leverage = 1 / (1 - collat)
        print(f'collat: {collat:.5%}')
        print(f'leverage: {leverage:.5f}x')
        print('liquidity:', strategy.getLiquidity().to('ether'))
        if collat >= strategy.collateralTarget() / 1.001e18:
            print('target leverage reached')
            break
    
    print('\nharvest')
    before = strategy.balanceOf()
    blocks_per_year = 2_300_000
    sample = 100
    chain.mine(sample)
    strategy.harvest()
    after = strategy.balanceOf()
    assert after >= before
    print('balance increase:', (after - before).to('ether'))
    print(f'implied apr: {(after / before - 1) * (blocks_per_year / sample):.8%}')

    vault.withdrawAll({'from': whale})
    user_after = dai.balanceOf(whale)
    print(f'\nuser balance increase:', (user_after - user_before).to('ether'))
    assert user_after >= user_before

    for i in count(1):
        print(f'\ndeleverage {i}')
        strategy.emergencyDeleverage()
        print('balance of strategy:', strategy.balanceOf().to('ether'))
        deposits, borrows = strategy.getCurrentPosition()
        print('deposits:', Wei(deposits).to('ether'))
        print('borrows:', Wei(borrows).to('ether'))
        collat = borrows / deposits
        leverage = 1 / (1 - collat)
        print(f'collat: {collat:.5%}')
        print(f'leverage: {leverage:.5f}x')
        print('liquidity:', strategy.getLiquidity().to('ether'))
        if borrows == 0:
            print('successfully deleveraged')
            break
