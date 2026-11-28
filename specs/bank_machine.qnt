// 銀行の状態機械（段階 02：bank.qnt の関数を action から呼んで、状態の遷移として書く）
//
// 状態は 3 つの var：口座（accounts）・直前の操作（lastOp）・その結果（lastOutcome）。
// lastOp と lastOutcome は、銀行そのものには要らないが、トレースを読むとき（段階 03）と、
// トレースを Rails の実装に流すとき（段階 05）に、どの操作が選ばれて成功したかを知るために持つ。
//
// テストは bank_machine_test.qnt。確かめ方：
//   scripts/check-specs.sh specs/bank_machine.qnt specs/bank_machine_test.qnt
//   npx quint run --max-steps=5 specs/bank_machine.qnt         # ランダムな実行を 1 つ表示する
module bank_machine {
  import bank.* from "./bank"

  // ---- 操作と結果 ----

  // 選ばれた操作。トレースに出すので、引数ごと残す
  type Op =
    | Init
    | Deposit({ id: AccountId, amount: int })
    | Withdraw({ id: AccountId, amount: int })
    | Transfer({ src: AccountId, dst: AccountId, amount: int })

  type Outcome =
    | Success
    | Failure(BankError)

  // ---- 状態 ----

  var accounts: Accounts
  var lastOp: Op
  var lastOutcome: Outcome

  // ---- 定数（step が選ぶ値の範囲） ----

  // carol は口座のない ID（存在しない口座への操作も選ばれるようにする）
  pure val IDS: Set[AccountId] = Set("alice", "bob", "carol")
  // 0 と負の数も入れて、失敗する操作も選ばれるようにする
  pure val AMOUNTS: Set[int] = (-1).to(30)
  pure val INITIAL: Accounts = Map("alice" -> 50, "bob" -> 20)

  // ---- action ----

  action init = all {
    accounts' = INITIAL,
    lastOp' = Init,
    lastOutcome' = Success,
  }

  // bank の関数の結果を、状態に反映する。失敗したら口座は変えず、理由を残す。
  // action の中では、すべての var に次の値（x' = …）を決める。match の枝ごとに決めてもよい
  // （どの枝でも accounts' と lastOutcome' を決めている）。1 つでも決め忘れた action を init.then(…) で
  // つなぐと、typecheck が作用（effect）の検査で "Expected [x,y] and [x] to be the same" のエラーにする
  // （quint 0.33.1 で動かして確かめた。実行する前に見つかる）
  action applyResult(op: Op, result: BankResult): bool = all {
    lastOp' = op,
    match result {
      | Ok(updated) => all { accounts' = updated, lastOutcome' = Success }
      | Err(e) => all { accounts' = accounts, lastOutcome' = Failure(e) }
    },
  }

  action doDeposit(id: AccountId, amount: int): bool =
    applyResult(Deposit({ id: id, amount: amount }), deposit(accounts, id, amount))

  action doWithdraw(id: AccountId, amount: int): bool =
    applyResult(Withdraw({ id: id, amount: amount }), withdraw(accounts, id, amount))

  action doTransfer(src: AccountId, dst: AccountId, amount: int): bool =
    applyResult(Transfer({ src: src, dst: dst, amount: amount }), transfer(accounts, src, dst, amount))

  // ---- witness（quint run --witnesses で、真になったトレースの数を数える） ----
  //
  // npx quint run specs/bank_machine.qnt --max-samples=1000 --max-steps=10 --witnesses transferSucceeded
  // で、送金が成功する実行がどれくらい選ばれるかを見る。1000 本のうち 436 本（43.6%）だった（seed による）。
  // --witnesses は値をいくつも取るので、ファイルの名前はその前に書く（後ろに書くと、ファイルの名前も
  // witness の名前として読まれ "Not enough non-option arguments" になる）。
  // witness は「トレースのどこかで真になったか」を数える。lastOutcome == Success は init で真なので、100% になる
  // （quint 0.33.1 で動かして確かめた）
  val transferSucceeded = match lastOp {
    | Transfer(_) => lastOutcome == Success
    | _ => false
  }

  // 1 歩：nondet で値を選び、any で操作を 1 つ選ぶ。quint run は、選び方をランダムに変えて何度も動かす
  action step = {
    nondet id = IDS.oneOf()
    nondet other = IDS.oneOf()
    nondet amount = AMOUNTS.oneOf()
    any {
      doDeposit(id, amount),
      doWithdraw(id, amount),
      doTransfer(id, other, amount),
    }
  }
}
