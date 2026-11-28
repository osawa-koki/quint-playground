// bank_concurrent.qnt のテスト（段階 03）
//
// quint run が見つけた反例と同じ型の割り込みを、手順の順を固定して再現する。
// 初めの残高は alice 50・bob 20（総額 70）。t1 が alice → bob に 30、t2 が bob → alice に 10 を送る。
//
// 確かめ方：scripts/check-specs.sh specs/bank_concurrent_test.qnt
//
// わかったこと（quint 0.33.1 で動かして確かめた）：
// - A.fail() は「A が選べない（条件が偽）」ことを確かめる。ただし run の最後にしか置けない。あとに .then・.expect を
//   続けると、次の状態がないので QNT502 "Variable … not set" で失敗する。途中で「選べない」を確かめるときは、
//   action の条件を def に分けて、.expect(not(条件)) で確かめる（canAcquire）
module bank_concurrent_test {
  import bank.* from "./bank"
  import bank_concurrent.* from "./bank_concurrent"

  // ロックなし：t2 が bob を読んだあと、t1 が bob に 30 を足し、t2 が古い bob（20）から 10 を引いた値で上書きする。
  // t1 が bob に足した 30 が消え、総額が 70 から 40 になる（lost update）
  run lostUpdateWithoutLocksTest =
    init
      .then(begin("t1", "alice", "bob", 30, false))
      .then(begin("t2", "bob", "alice", 10, false))
      .then(read("t1"))       // t1 が読む：alice 50・bob 20
      .then(writeSrc("t1"))   // alice = 50 − 30 = 20
      .then(read("t2"))       // t2 が読む：bob 20・alice 20（t1 はまだ bob に足していない）
      .then(writeDst("t1"))   // bob = 20 + 30 = 50
      .then(writeSrc("t2"))   // bob = 20 − 10 = 10（t2 が読んだ古い 20 から計算して、t1 の 30 を消す）
      .then(writeDst("t2"))   // alice = 20 + 10 = 30
      .expect(and {
        balances == Map("alice" -> 30, "bob" -> 10),
        totalBalance(balances) == 40,
        not(moneyConserved),
        noNegativeBalance,    // 残高は負にならない。壊れるのは総額だけ
      })

  // ロックあり：t1 がロックを持っている間、t2 はロックを取れない（acquire が選べない）ので、
  // 上の割り込みは起きない。t1 が終わってから t2 が進み、総額は 70 のまま
  run locksPreventLostUpdateTest =
    init
      .then(begin("t1", "alice", "bob", 30, true))
      .then(begin("t2", "bob", "alice", 10, true))
      .then(acquire("t1"))
      .then(read("t1"))
      .then(writeSrc("t1"))
      .expect(not(canAcquire("t2")))  // t1 が alice・bob のロックを持っているので、t2 はロックを取れない
      .then(writeDst("t1"))        // t1 が終わり、ロックを外す
      .then(acquire("t2"))
      .then(read("t2"))            // t2 が読む：bob 50・alice 20（t1 の結果を読む）
      .then(writeSrc("t2"))
      .then(writeDst("t2"))
      .expect(and {
        balances == Map("alice" -> 30, "bob" -> 40),
        moneyConserved,
        locks == Map("alice" -> Free, "bob" -> Free),
      })

  // 残高が足りなければ、読んだところで送金をやめ、ロックも外す
  run insufficientFundsReleasesLocksTest =
    init
      .then(begin("t1", "bob", "alice", 30, true))
      .then(acquire("t1"))
      .then(read("t1"))   // bob は 20 しかない
      .expect(and {
        txs.get("t1").pc == Idle,
        balances == INITIAL,
        locks == Map("alice" -> Free, "bob" -> Free),
      })

  // 同じ口座への送金と、0 以下の金額は始められない（.fail() は run の最後に置く）
  run sameAccountCannotBeginTest =
    init.then(begin("t1", "alice", "alice", 10, false).fail())

  run nonPositiveAmountCannotBeginTest =
    init.then(begin("t1", "alice", "bob", 0, false).fail())

  // 動いている送金は、もう一度始められない
  run busyTxCannotBeginTest =
    init
      .then(begin("t1", "alice", "bob", 10, false))
      .then(begin("t1", "bob", "alice", 10, false).fail())
}
