// bank_machine.qnt のテスト（段階 02）
//
// 確かめ方：scripts/check-specs.sh specs/bank_machine_test.qnt
//
// わかったこと（quint 0.33.1 で動かして確かめた）：
// - A.then(B) で action をつなぐと、決まった操作の列の実行を作れる。.expect(条件) で、その時点の状態を確かめる
// - expect のあとにも .then(…) でつなげる（途中の状態を何度も確かめられる）
// - nondet を含む action（step）を使う run は、quint test が乱数を変えて何度も動かす（既定で 10000 回）
// - n.reps(i => A) は、A を n 回つなぐ
module bank_machine_test {
  import bank.* from "./bank"
  import bank_machine.* from "./bank_machine"

  // ---- テスト：then で操作をつないで、決まった実行を作る ----

  run initTest =
    init.then(all {
      assert(accounts == INITIAL),
      assert(lastOp == Init),
      assert(lastOutcome == Success),
      accounts' = accounts, lastOp' = lastOp, lastOutcome' = lastOutcome,
    })

  run successfulSequenceTest =
    init
      .then(doDeposit("alice", 10))
      .then(doWithdraw("bob", 5))
      .then(doTransfer("alice", "bob", 30))
      .expect(and {
        accounts == Map("alice" -> 30, "bob" -> 45),
        lastOp == Transfer({ src: "alice", dst: "bob", amount: 30 }),
        lastOutcome == Success,
      })

  // 失敗した操作は口座を変えず、理由が残る
  run failureKeepsAccountsTest =
    init
      .then(doWithdraw("bob", 21))
      .expect(and {
        accounts == INITIAL,
        lastOutcome == Failure(InsufficientFunds),
      })

  // 失敗をはさんでも、前後の成功した操作はそのまま効く
  run mixedSequenceTest =
    init
      .then(doTransfer("alice", "bob", 50))       // alice: 0, bob: 70
      .then(doTransfer("alice", "bob", 1))        // 残高不足で失敗
      .expect(lastOutcome == Failure(InsufficientFunds))
      .then(doDeposit("carol", 5))                // 口座がなくて失敗
      .expect(lastOutcome == Failure(UnknownAccount))
      .then(doTransfer("bob", "alice", 70))       // alice: 70, bob: 0
      .expect(and {
        accounts == Map("alice" -> 70, "bob" -> 0),
        lastOutcome == Success,
      })

  // step を何度動かしても、実行が止まらない（どの状態からも、選べる操作がある）
  run stepNeverDeadlocksTest =
    init.then(10.reps(_ => step))
}
