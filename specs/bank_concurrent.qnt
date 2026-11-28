// 同時に動く送金（段階 03：送金を手順に分けて、割り込みで起きる不具合を見る）
//
// bank_machine では、送金は 1 歩で終わる（原子的な）操作だった。実装（Rails など）では、送金は
//   1. 元と先の口座を読み込む（残高をメモリに持つ）
//   2. 元の残高 = 読んだ値 − 金額 を保存する
//   3. 先の残高 = 読んだ値 + 金額 を保存する
// の手順に分かれ、手順の間に、ほかの送金の手順が割り込みうる。ここでは、2 つの送金（t1・t2）の手順が
// 好きな順に割り込み合う状態機械を書き、2 つの step を比べる：
//   - stepUnsafe：ロックを取らない。読んでから書くまでの間に、ほかの送金が同じ口座を書き換えると、
//                 古い値で上書きして、その送金の分が消える（lost update）
//   - stepLocked：読む前に、元と先の両方の口座のロックを取る（Rails なら transaction の中で lock! する）
//
// 確かめ方：
//   scripts/check-specs.sh specs/bank_concurrent.qnt specs/bank_concurrent_test.qnt
//   scripts/check-invariants.sh bank_concurrent_unsafe bank_concurrent_locked
//   npx quint run specs/bank_concurrent.qnt --step=stepUnsafe --invariants noNegativeBalance moneyConserved
//
// わかったこと（quint 0.33.1 で動かして確かめた）：
// - stepUnsafe では、quint run がほぼ 1〜2 本めのトレースで moneyConserved の反例を出す（seed を 5 つ変えて確かめた）。
//   反例を読むと、t2 が口座を読んでから書くまでの間に、t1 が同じ口座を書き換えていて、t2 が古い値から計算した
//   残高で上書きしている。この割り込みの順を固定したのが bank_concurrent_test の lostUpdateWithoutLocksTest
// - stepUnsafe でも noNegativeBalance は破られない（1 万本 × 20 歩）。書く値は「読んだ値 − 金額」で、読んだ値は
//   金額以上なので負にならない。この型の不具合で壊れるのは、残高の正しさ（総額）のほうで、残高の確かめでは見つからない。
//   （ここからは考え方で、この仕様では確かめていない）実装が「いまの残高から引く」（SQL の balance = balance - x）なら、
//   逆に総額は守られ、残高の確かめ（読んだ時点の残高で足りるか）が古くなって、負になりうる。段階 05 の Rails で確かめる
// - stepLocked では、1 万本 × 30 歩で 3 つの不変条件が破られない（約 1 秒）。witness で、2 つの送金が同時に動く・
//   ロックを待つ場面が、どのトレースにも現れることを確かめた（何も起きないから守られている、のではない）
// - マップの値の集合を返す演算子（values のようなもの）はない（QNT404）。キーを回して調べる
module bank_concurrent {
  import bank.* from "./bank"

  // ---- 型 ----

  type TxId = str

  // 送金の手順のどこにいるか（プログラムカウンタ）
  type Pc =
    | Idle        // 動いていない（次の送金を始められる）
    | ToLock      // ロックを取る前（stepLocked のときだけ通る）
    | ToRead      // 口座を読む前
    | ToWriteSrc  // 元の口座を書く前
    | ToWriteDst  // 先の口座を書く前（元からはもう引いてある）

  type Tx = {
    pc: Pc,
    src: AccountId,
    dst: AccountId,
    amount: int,
    readSrc: int,  // 手順 1 で読んだ元の残高（メモリに持った値）
    readDst: int,  // 手順 1 で読んだ先の残高
    locking: bool, // ロックを取る送金か
  }

  // 口座のロックを、誰が持っているか
  type Holder =
    | Free
    | HeldBy(TxId)

  // ---- 定数 ----

  pure val TXS: Set[TxId] = Set("t1", "t2")
  pure val IDS: Set[AccountId] = Set("alice", "bob")
  pure val AMOUNTS: Set[int] = Set(10, 20, 30)
  pure val INITIAL: Accounts = Map("alice" -> 50, "bob" -> 20)
  pure val IDLE_TX: Tx = { pc: Idle, src: "", dst: "", amount: 0, readSrc: 0, readDst: 0, locking: false }

  // ---- 状態 ----

  var balances: Accounts          // 保存されている残高（DB）
  var txs: TxId -> Tx             // 送金ごとの手順と、メモリに持った値
  var locks: AccountId -> Holder  // 口座ごとのロック

  // ---- action ----

  action init = all {
    balances' = INITIAL,
    txs' = TXS.mapBy(_ => IDLE_TX),
    locks' = IDS.mapBy(_ => Free),
  }

  // t が持っているロックを外したロックの表
  def released(t: TxId): AccountId -> Holder =
    locks.keys().mapBy(id => if (locks.get(id) == HeldBy(t)) Free else locks.get(id))

  // 送金を始める。口座の確かめ（存在する・同じでない・金額が正）は、始めるときにする
  action begin(t: TxId, src: AccountId, dst: AccountId, amount: int, locking: bool): bool = all {
    txs.get(t).pc == Idle,
    src != dst,
    amount > 0,
    txs' = txs.set(t, { pc: if (locking) ToLock else ToRead, src: src, dst: dst, amount: amount,
                        readSrc: 0, readDst: 0, locking: locking }),
    balances' = balances,
    locks' = locks,
  }

  // 元と先の両方のロックを、まとめて取る。どちらかが取られていたら、この action は選べない（待つ）。
  // 1 つずつ取ると、t1 が alice → bob、t2 が bob → alice の順に取ってデッドロックしうるので、まとめて取る
  // （実装なら、口座の ID の順に lock! するのと同じ効き目）
  // acquire を選べるか。テストで「いまはロックを取れない」を確かめるために、条件だけを def に分けた
  def canAcquire(t: TxId): bool = {
    val tx = txs.get(t)
    and {
      tx.pc == ToLock,
      locks.get(tx.src) == Free,
      locks.get(tx.dst) == Free,
    }
  }

  action acquire(t: TxId): bool = {
    val tx = txs.get(t)
    all {
      canAcquire(t),
      locks' = locks.set(tx.src, HeldBy(t)).set(tx.dst, HeldBy(t)),
      txs' = txs.set(t, { ...tx, pc: ToRead }),
      balances' = balances,
    }
  }

  // 手順 1：元と先の残高を読む。残高が足りなければ、ここで送金をやめる（ロックも外す）
  action read(t: TxId): bool = {
    val tx = txs.get(t)
    val srcBalance = balances.get(tx.src)
    all {
      tx.pc == ToRead,
      if (srcBalance < tx.amount) all {
        txs' = txs.set(t, IDLE_TX),
        locks' = released(t),
      } else all {
        txs' = txs.set(t, { ...tx, pc: ToWriteSrc, readSrc: srcBalance, readDst: balances.get(tx.dst) }),
        locks' = locks,
      },
      balances' = balances,
    }
  }

  // 手順 2：元の残高を「読んだ値 − 金額」で上書きする（いまの残高ではなく、メモリに持った値から計算する）
  action writeSrc(t: TxId): bool = {
    val tx = txs.get(t)
    all {
      tx.pc == ToWriteSrc,
      balances' = balances.set(tx.src, tx.readSrc - tx.amount),
      txs' = txs.set(t, { ...tx, pc: ToWriteDst }),
      locks' = locks,
    }
  }

  // 手順 3：先の残高を「読んだ値 + 金額」で上書きして、送金を終える（ロックも外す）
  action writeDst(t: TxId): bool = {
    val tx = txs.get(t)
    all {
      tx.pc == ToWriteDst,
      balances' = balances.set(tx.dst, tx.readDst + tx.amount),
      txs' = txs.set(t, IDLE_TX),
      locks' = released(t),
    }
  }

  // 1 歩：どれかの送金の、どれかの手順を進める
  action stepWith(locking: bool): bool = {
    nondet t = TXS.oneOf()
    nondet src = IDS.oneOf()
    nondet dst = IDS.oneOf()
    nondet amount = AMOUNTS.oneOf()
    any {
      begin(t, src, dst, amount, locking),
      acquire(t),
      read(t),
      writeSrc(t),
      writeDst(t),
    }
  }

  action stepUnsafe = stepWith(false)
  action stepLocked = stepWith(true)

  // ---- 不変条件 ----

  // 送金の途中で、元から引いたが先にまだ足していないお金
  val inFlight: int = TXS.fold(0, (sum, t) => {
    val tx = txs.get(t)
    if (tx.pc == ToWriteDst) sum + tx.amount else sum
  })

  // 残高が負にならない
  val noNegativeBalance = allNonNegative(balances)

  // 途中のお金も数えると、総額は変わらない（銀行の中で送金しているだけなので）
  val moneyConserved = totalBalance(balances) + inFlight == totalBalance(INITIAL)

  // ロックを取る送金は、読んでから終えるまで、元と先の両方のロックを持っている
  val locksHeld = TXS.forall(t => {
    val tx = txs.get(t)
    (tx.locking and Set(ToRead, ToWriteSrc, ToWriteDst).contains(tx.pc)) implies and {
      locks.get(tx.src) == HeldBy(t),
      locks.get(tx.dst) == HeldBy(t),
    }
  })

  // ---- witness（不変条件が「何も起きないから」守られているのではないことを確かめる） ----

  // 2 つの送金が同時に動いている（どちらも Idle でない）
  val bothActive = TXS.forall(t => txs.get(t).pc != Idle)

  // 送金が、元から引いて先に足す前まで進んだ
  val reachedWriteDst = TXS.exists(t => txs.get(t).pc == ToWriteDst)

  // ロックを待っている送金がある（もう 1 つの送金がロックを持っている）。
  // マップに値の集合を返す演算子（values のようなもの）はなく、QNT404 になるので、キーを回して調べる
  val waitingForLock = TXS.exists(t => and {
    txs.get(t).pc == ToLock,
    TXS.exists(u => u != t and IDS.exists(id => locks.get(id) == HeldBy(u))),
  })
}

