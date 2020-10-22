from brownie import Wei, reverts


def initialMigrate(strategy,vault, whale, ychad, dai, controller):
    print('\n----migrating strategy----')
    controller.approveStrategy(dai, strategy, {'from': ychad})
    controller.setStrategy(dai, strategy, {'from': ychad})
    vault.setMin(10000, {'from': ychad})
    assert controller.strategies(dai) == strategy
    daiInVault = dai.balanceOf(vault)
    earn(strategy, vault, ychad)
    deposit('10000 ether', whale, dai, vault)
    earn(strategy, vault, ychad)

    assert(dai.balanceOf(vault) == 0, "All money should now be in strat")
    assert(dai.balanceOf(strategy) == 0, "All money in strat should be invested")
  
    deposits, borrows = strategy.getCurrentPosition()
    assert(borrows > 0, "Should have borrowed some")
    assert(deposits > 0, "Should have lent some")

def harvest(strategy, user):
    print('\n----bot calls harvest----')
    strategy.harvest({'from': user})
    stateOf(strategy)

def earn(strategy, vault, user):
    print('\n----bot calls earn----')
    vault.earn({'from': user})
    stateOf(strategy)

def stateOf(strategy):
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
    
    assert( collat < strategy.collateralTarget(), "Over collateral target!")


def deposit(amount, whale, dai, vault):
    weiAmount = Wei(amount)
    print('\n----user deposits----')
    dai.approve(vault, weiAmount, {'from': whale})
    print('deposit amount:', weiAmount.to('ether'))
    vault.deposit(weiAmount, {'from': whale})
    assert(dai.balanceOf(vault) == weiAmount, "Balance not arrived in vault")

def withdraw(share, strategy,whale, dai, vault):
    toWithdraw = 1/share
    print(f'\n----user withdraws {toWithdraw} share----')
    balanceBefore = dai.balanceOf(whale)
    vault.withdraw(vault.balanceOf(whale)/toWithdraw, {'from': whale})
    balanceAfter = dai.balanceOf(whale)
    moneyOut = balanceAfter-balanceBefore
    print('Money Out:', Wei(moneyOut).to('ether'))

    stateOf(strategy)