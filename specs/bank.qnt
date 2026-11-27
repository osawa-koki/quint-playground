// 銀行の口座と、入金・出金・送金（段階 01：状態を持たない関数だけで書く）
//
// 口座は「口座の ID → 残高」のマップで表す。操作は口座のマップを受け取り、成功なら新しいマップ、
// 失敗なら理由を返す（もとのマップは変えない）。段階 02 では、この関数を action から呼んで状態機械にする。
//
// 確かめ方：scripts/check-specs.sh specs/bank.qnt（quint typecheck と quint test）
//
// わかったこと（quint 0.33.1 で動かして確かめた）：
// - 直和型（type T = | A | B(x)）は == で比べられる。テストで「結果がこの Err か」を 1 行で書ける
// - to・next は組み込みの名前で、引数や match の変数に使うと QNT101 になる（from は使える）
// - run の中の all { assert(…), … } は、どれか 1 つでも偽なら QNT508 "Assertion failed" で失敗する
// - tuples(A, B, …) と forall で、小さな範囲のすべての組み合わせを調べられる（864 通りで 1 秒もかからない）
// - テストが不具合を見つけるかは、わざと壊して確かめた：出金の残高の確認を消すと 4 つ、
//   送金の入金を amount + 1 にすると 2 つのテストが失敗した
module bank {
  // ---- 型 ----

  type AccountId = str

  // 口座の ID → 残高。残高は整数（Quint の int は大きさに上限のない整数）
  type Accounts = AccountId -> int

  // 失敗の理由。引数のない構成子だけの直和型は、列挙型のように使える
  type BankError =
    | UnknownAccount     // 存在しない口座
    | NonPositiveAmount  // 金額が 0 以下
    | InsufficientFunds  // 残高が足りない
    | SameAccount        // 送金の元と先が同じ口座

  // 操作の結果。Ok は新しい口座のマップ、Err は理由を持つ
  type BankResult =
    | Ok(Accounts)
    | Err(BankError)

  // ---- 問い合わせ ----

  pure def hasAccount(accounts: Accounts, id: AccountId): bool =
    accounts.keys().contains(id)

  // すべての口座の残高の合計。マップに sum のような演算子はないので、キーの集合を fold で足す
  pure def totalBalance(accounts: Accounts): int =
    accounts.keys().fold(0, (sum, id) => sum + accounts.get(id))

  // すべての残高が 0 以上か
  pure def allNonNegative(accounts: Accounts): bool =
    accounts.keys().forall(id => accounts.get(id) >= 0)

  // ---- 操作 ----

  // 入金：口座があり、金額が正なら、残高を増やす
  pure def deposit(accounts: Accounts, id: AccountId, amount: int): BankResult =
    if (not(hasAccount(accounts, id))) Err(UnknownAccount)
    else if (amount <= 0) Err(NonPositiveAmount)
    else Ok(accounts.setBy(id, balance => balance + amount))

  // 出金：口座があり、金額が正で、残高が足りるなら、残高を減らす
  pure def withdraw(accounts: Accounts, id: AccountId, amount: int): BankResult =
    if (not(hasAccount(accounts, id))) Err(UnknownAccount)
    else if (amount <= 0) Err(NonPositiveAmount)
    else if (accounts.get(id) < amount) Err(InsufficientFunds)
    else Ok(accounts.setBy(id, balance => balance - amount))

  // 送金：元（src）から出金して、先に入金する。どちらかが失敗したら、全体が失敗（途中の状態を返さない）
  // 元と先が同じ口座は、総額は変わらないが意味のない操作なので、失敗にする
  // 引数の名前に to・next は使えない（Quint の組み込みの名前。to は 0.to(3) の範囲、next は次の状態の演算子）。
  // 使うと QNT101 "Built-in name 'to' is redefined" になる（quint 0.33.1 で動かして確かめた）
  pure def transfer(accounts: Accounts, src: AccountId, dst: AccountId, amount: int): BankResult =
    if (not(hasAccount(accounts, src)) or not(hasAccount(accounts, dst))) Err(UnknownAccount)
    else if (src == dst) Err(SameAccount)
    else match withdraw(accounts, src, amount) {
      | Ok(afterWithdraw) => deposit(afterWithdraw, dst, amount)
      | Err(e) => Err(e)
    }

  // ---- テスト（quint test は、名前が Test で終わる run を動かす） ----

  pure val sample: Accounts = Map("alice" -> 100, "bob" -> 50)

  run depositTest = all {
    assert(deposit(sample, "alice", 30) == Ok(Map("alice" -> 130, "bob" -> 50))),
    assert(deposit(sample, "carol", 30) == Err(UnknownAccount)),
    assert(deposit(sample, "alice", 0) == Err(NonPositiveAmount)),
    assert(deposit(sample, "alice", -5) == Err(NonPositiveAmount)),
  }

  run withdrawTest = all {
    assert(withdraw(sample, "bob", 20) == Ok(Map("alice" -> 100, "bob" -> 30))),
    // 残高をちょうど使い切るのは成功
    assert(withdraw(sample, "bob", 50) == Ok(Map("alice" -> 100, "bob" -> 0))),
    assert(withdraw(sample, "bob", 51) == Err(InsufficientFunds)),
    assert(withdraw(sample, "carol", 1) == Err(UnknownAccount)),
    assert(withdraw(sample, "bob", 0) == Err(NonPositiveAmount)),
  }

  run transferTest = all {
    assert(transfer(sample, "alice", "bob", 40) == Ok(Map("alice" -> 60, "bob" -> 90))),
    assert(transfer(sample, "bob", "alice", 51) == Err(InsufficientFunds)),
    assert(transfer(sample, "alice", "carol", 1) == Err(UnknownAccount)),
    assert(transfer(sample, "carol", "alice", 1) == Err(UnknownAccount)),
    assert(transfer(sample, "alice", "alice", 1) == Err(SameAccount)),
    assert(transfer(sample, "alice", "bob", 0) == Err(NonPositiveAmount)),
  }

  // 失敗の理由が複数当てはまるときは、先に調べたもの（口座 → 同じ口座 → 金額 → 残高）が返る
  run errorPriorityTest = all {
    assert(transfer(sample, "carol", "carol", -1) == Err(UnknownAccount)),
    assert(transfer(sample, "alice", "alice", -1) == Err(SameAccount)),
    assert(transfer(sample, "alice", "bob", -1) == Err(NonPositiveAmount)),
  }

  // ---- 網羅のテスト：小さな範囲のすべての組み合わせで、性質を確かめる ----
  //
  // tuples で直積の集合を作り、forall で全部を調べる。乱数ではなく全部の組み合わせなので、
  // この範囲では漏れがない（範囲の外は確かめていない。網羅的に確かめるのは段階 04 の quint verify）

  pure val ids: Set[AccountId] = Set("alice", "bob", "carol")  // carol は口座のない ID
  pure val balances: Set[int] = 0.to(3)
  pure val amounts: Set[int] = (-1).to(4)

  // alice と bob の残高のすべての組み合わせ（4 × 4 = 16 通り）
  pure val allAccounts: Set[Accounts] =
    tuples(balances, balances).map(((a, b)) => Map("alice" -> a, "bob" -> b))

  // 送金が成功したら、総額が変わらず、残高が負にならない（16 × 3 × 3 × 6 = 864 通り）
  run transferPreservesInvariantsTest = assert(
    tuples(allAccounts, ids, ids, amounts).forall(((accounts, src, dst, amount)) =>
      match transfer(accounts, src, dst, amount) {
        | Ok(after) => and {
            totalBalance(after) == totalBalance(accounts),
            allNonNegative(after),
            after.keys() == accounts.keys(),  // 口座が増えたり減ったりしない
          }
        | Err(_) => true
      }
    )
  )

  // 送金が失敗するのは、理由があるときだけ（成功すべきときに失敗していない）
  run transferSucceedsWhenValidTest = assert(
    tuples(allAccounts, ids, ids, amounts).forall(((accounts, src, dst, amount)) =>
      val valid = and {
        hasAccount(accounts, src),
        hasAccount(accounts, dst),
        src != dst,
        amount > 0,
        accounts.get(src) >= amount,
      }
      match transfer(accounts, src, dst, amount) {
        | Ok(_) => valid
        | Err(_) => not(valid)
      }
    )
  )
}
