// 銀行の口座と、入金・出金・送金（段階 01：状態を持たない関数だけで書く）
//
// 口座は「口座の ID → 残高」のマップで表す。操作は口座のマップを受け取り、成功なら新しいマップ、
// 失敗なら理由を返す（もとのマップは変えない）。段階 02 では、この関数を action から呼んで状態機械にする。
//
// テストは bank_test.qnt。確かめ方：scripts/check-specs.sh specs/bank.qnt specs/bank_test.qnt
//
// わかったこと（quint 0.33.1 で動かして確かめた）：
// - 直和型（type T = | A | B(x)）は == で比べられる。テストで「結果がこの Err か」を 1 行で書ける
// - to・next は組み込みの名前で、引数や match の変数に使うと QNT101 になる（from は使える）
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
}
