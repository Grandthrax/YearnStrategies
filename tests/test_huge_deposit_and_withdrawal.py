from itertools import count
from brownie import Wei, reverts
import brownie

def test_huge_deposit_and_withdrawal(accounts, interface, chain, web3, history, YearnCompDaiStrategy):
    user = accounts[0]
    #whale has 29m dai
    whale = accounts.at("0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", force=True)
    ychad = accounts.at(web3.ens.resolve('ychad.eth'), force=True)

    solo = interface.ISoloMargin('0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e')
    comptroller = interface.ComptrollerI('0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b')
    dai = interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')
    cdai = interface.CErc20I('0x5d3a536e4d6dbd6114cc1ead35777bab948e3643')
    comp = interface.ERC20('0xc00e94cb662c3520282e6f5717214004a7f26888')

    controller = interface.IController('0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080')
    vault = interface.IVault(controller.vaults(dai))

    print(dai.balanceOf('0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3'))

    strategy = YearnCompDaiStrategy.deploy(controller, {'from': user})
    assert strategy.want() == vault.token() == dai
    strategy.setWithdrawalFee(0)
    
    print('migrate strategy')
    controller.approveStrategy(dai, strategy, {'from': ychad})
    controller.setStrategy(dai, strategy, {'from': ychad})
    vault.setMin(10000, {'from': ychad})
    assert controller.strategies(dai) == strategy
    print('dai in vault:', dai.balanceOf(vault).to('ether'))

    print('\n----deposit funds into new strategy----')
    vault.earn({'from': user})
    depositsO, borrows = strategy.getCurrentPosition()
    print('deposits:', Wei(depositsO).to('ether'))
    print('borrows:', Wei(borrows).to('ether'))  
    if depositsO == 0:
        collat = 0 
    else:
        collat = borrows / depositsO
    leverage = 1 / (1 - collat)
    print(f'collat: {collat:.5%}')
    print(f'leverage: {leverage:.5f}x')
    print('liquidity:', strategy.getLiquidity().to('ether'))

    

    print('\n----whale deposits----')
    
    #amount =dai.balanceOf(whale)
    amount = Wei('10000000 ether')
    dai.approve(vault, amount, {'from': whale})
    print('deposit amount:', amount.to('ether'))
    vault.deposit(amount, {'from': whale})
    vault.earn({'from': user})

    deposits, borrows = strategy.getCurrentPosition()
    assert deposits > depositsO
    print('deposits:', Wei(deposits).to('ether'))
    print('borrows:', Wei(borrows).to('ether'))  
    if deposits == 0:
        collat = 0 
    else:
        collat = borrows / deposits
    leverage = 1 / (1 - collat)
    print(f'collat: {collat:.5%}')
    print(f'leverage: {leverage:.5f}x')
    print('liquidity:', strategy.getLiquidity().to('ether'))

    #print('\n----disabling Aave----')
    #strategy.disableAave({'from': user})

    for i in count(1):
        print(f'\ndeposit {i}')
        strategy.harvest({'from': user})
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


    print('\n----whale withdraws large amount----')
   
    user_before = dai.balanceOf(whale)
    tx = vault.withdrawAll({'from': whale})
    print(tx.events['Leverage'])
    #print(tx.info())
    user_after = dai.balanceOf(whale)
    print(f'\nWhale withdrew:', (user_after - user_before).to('ether'))
    deposits, borrows = strategy.getCurrentPosition()
    print('deposits:', Wei(deposits).to('ether'))
    print('borrows:', Wei(borrows).to('ether'))  
    if deposits == 0:
        collat = 0 
    else:
        collat = borrows / deposits
    leverage = 1 / (1 - collat)
    print(f'collat: {collat:.5%}')
    print(f'leverage: {leverage:.5f}x')


