//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — M1 TIER + M2 SCALP TIER,            |
//|                               HARD M1/M2/M5 TP, 5-BAND RISK       |
//| Magic 20260872. A fork of the hard-TP build                       |
//| (experimental-bottomup-stack-m1m2-scalp-m30-bias-hardtp-ea.mq5,   |
//| magic 20260871), which is left untouched.                         |
//|                                                                  |
//|------------------------------------------------------------------|
//| THREE CHANGES                                                    |
//|                                                                  |
//| 1. A SEVENTH TIER: M1, ALONE.                                    |
//|    The chain is `CheckAlign(M1) != 0` and NOTHING else — no       |
//|    higher timeframe confirms it. This breaks the rule the whole   |
//|    family was built on ("M1 alone never trades; it is only the    |
//|    start of the stack"), deliberately and behind `InpM1Tier`.     |
//|    Its bias is M30 alone (`InpM1M30Bias`), the same gate the M2   |
//|    scalp uses, so it may trade while H4 is flat AND against an    |
//|    aligned H4. Expect a high trade count and no higher-TF         |
//|    agreement whatsoever — this is the least confirmed entry in    |
//|    the file by a wide margin.                                     |
//|                                                                  |
//|    THE LEVEL INDEX NOW EQUALS THE TF INDEX. With M1 tradable the  |
//|    level list {M1,M2,M5,M15,M30,H1,H4} is exactly tfs[], so the   |
//|    parent's "lvl + 1" offset is gone from all 18 of its sites.    |
//|    LVL_* and IDX_* are equal by construction but both kept: they  |
//|    say different things at a call site (which TIER vs which TF).  |
//|    `ENUM_H1_BIAS_TIER` shifted up by one with them.               |
//|                                                                  |
//| 2. TARGETS RE-CUT, AND M1 GIVEN ONE — PLUS A TIGHT HARD STOP.    |
//|                                                                  |
//|      tier   TP      SL      reward:risk                          |
//|      M1     30p     20p     1.50 : 1                             |
//|      M2     40p     25p     1.60 : 1                             |
//|      M5     50p     30p     1.67 : 1                             |
//|      M15+   none    none (8xATR disaster stop only, as parent)   |
//|                                                                  |
//|    A pip is the gold convention, 0.10 of price, auto-resolved     |
//|    from SYMBOL_DIGITS, so M1 is a 2.00 stop against a 3.00        |
//|    target on gold.                                                |
//|                                                                  |
//|    THE HARD STOP REPLACES THE DISASTER STOP ON THESE THREE TIERS  |
//|    rather than sitting beside it, and is CLAMPED to the tighter   |
//|    of the fixed distance and 8xATR — on a volatile feed a fixed   |
//|    20 pips could otherwise exceed 8xATR and become a WIDER stop   |
//|    than the parent's, the opposite of the intent. The broker's    |
//|    minimum stop distance is still the floor: a stop too tight to  |
//|    place is widened to the nearest legal level, not dropped.      |
//|    M15 and above are untouched.                                   |
//|                                                                  |
//|    SIZING FOLLOWS THE REAL STOP, AND THIS IS THE IMPORTANT PART.  |
//|    RiskLots sized every tier against 2xATR while the stop sat at  |
//|    8xATR, which is why a stop-out has always cost ~4x the stated  |
//|    risk %. A fixed 20-pip stop has no fixed relationship to       |
//|    2xATR at all, so leaving sizing alone would have made the risk |
//|    table fiction on exactly the tiers this build is about.        |
//|    M1/M2/M5 are therefore sized on the stop they will actually    |
//|    run. The consequence, which MUST be read before comparing      |
//|    tiers:                                                         |
//|                                                                  |
//|      M1/M2/M5   stop-out costs ~1x the stated risk %             |
//|      M15..H4    stop-out costs ~4x the stated risk % (unchanged) |
//|                                                                  |
//|    The two halves of the risk ladder are no longer on one scale.  |
//|    OnInit prints this split rather than leaving it to be found.   |
//|                                                                  |
//| 3. THE RISK LADDER GOES FROM THREE BANDS TO FIVE, AND 13k+       |
//|    CARRIES MORE RISK.                                            |
//|    The parent cut H4 to 2.0% above 13000 — a 5x cliff below the   |
//|    7000-13000 band's 10.0%. Because the cut outran the equity     |
//|    growth, an account crossing 13000 risked FEWER DOLLARS than    |
//|    it had at 7000 ($448 against $1,321). The new ladder is        |
//|    anchored on H4 per band, every other tier holding the fixed    |
//|    fraction of it that bands 1 and 2 have always used:            |
//|                                                                  |
//|      band  equity          H4     total   $ at the band floor     |
//|      1     < 7000        20.0%   37.75%   $1,132 @ 3000          |
//|      2     7000-13000    10.0%   18.88%   $1,321 @ 7000          |
//|      3     13000-17000    7.0%   13.21%   $1,718 @ 13000         |
//|      4     17000-20000    4.0%    7.55%   $1,284 @ 17000         |
//|      5     20000+         2.0%    3.77%   $  755 @ 20000         |
//|                                                                  |
//|    Bands 1 and 2 are UNCHANGED.                                   |
//|                                                                  |
//|    THREE THINGS TO KNOW ABOUT THIS LADDER:                        |
//|    * 13000 IS NO LONGER A DE-RISKING POINT — IT IS A STEP UP.     |
//|      At H4 7.0% the band-3 floor risks $1,718 against band 2's    |
//|      $1,321, so crossing 13000 INCREASES money at risk by ~30%    |
//|      rather than holding it level. The de-risking now begins at   |
//|      17000. This is the intended shape, but it is the opposite of |
//|      what the parent's ladder did at this edge, so it is the      |
//|      first thing to re-read if drawdown past 13k looks wrong.     |
//|    * M30 in band 3 is 1.75%, against the parent's 0.20%. The      |
//|      parent's 13000+ band was the ONE place M30 broke the         |
//|      ladder's shape (0.10xH4 where every other band uses          |
//|      0.25xH4); the new bands restore the shape, so M30 gains      |
//|      more here than its neighbours do. Set InpRiskPctM30_T3 = 0.7 |
//|      to hold M30 at the old ratio instead.                        |
//|    * Band 5 MATCHES the parent's old 13000+ risk (H4 2.0%) rather |
//|      than going below it, so even the most conservative band here |
//|      is no tighter than what the parent applied from 13000 up.    |
//|                                                                  |
//|    The % in the inputs is the SIZING basis (2xATR). The disaster  |
//|    stop sits at 8xATR, so a full stop-out costs 4x the figure —   |
//|    band 1 is 151% at the disaster stop, band 3 52.9%, band 5      |
//|    15.1%. OnInit prints both, per band, with totals.              |
//|                                                                  |
//| ONE-POSITION RULE, NOW COVERING BOTH BOTTOM TIERS.                |
//| `HigherLiveLevelBusy()` became `OtherLevelBusy(s, lvl)`: it scans |
//| EVERY other level, not just the five live ones. Both M1 and M2    |
//| take their direction from M30 rather than H4, so either can open  |
//| against a running trade on ANY other tier — including each other, |
//| which the parent's version could not see. On a netting account    |
//| MT5 would net the opposing orders, shrinking or closing the live  |
//| trade behind the EA's back. `InpScalpNeedsFlatSymbol` governs     |
//| both tiers.                                                       |
//|                                                                  |
//|------------------------------------------------------------------|
//| INHERITED FROM THE HARD-TP PARENT, UNCHANGED:                    |
//+------------------------------------------------------------------+
//| Magic 20260871. A fork of the M1+M2 scalp-tier build              |
//| (experimental-bottomup-stack-m1m2-scalp-m30-bias-ea.mq5, magic    |
//| 20260870), which is left untouched. The scalp tier, its M30 bias, |
//| the five live tiers and every gate are inherited unchanged.       |
//|                                                                  |
//|------------------------------------------------------------------|
//| WHAT IS NEW: A HARD TAKE PROFIT ON M2 AND M5                     |
//|                                                                  |
//| The parent has NO profit target anywhere — every tier rides a     |
//| kumo-touch exit and the BE/chandelier layer, and only the wide    |
//| disaster stop is attached to the order. This build attaches a     |
//| broker-side TP to the two smallest tiers at the moment the order  |
//| goes out:                                                        |
//|                                                                  |
//|   M2 tier  -> InpTPPipsM2 (default 30 pips = 4000.00 -> 4003.00) |
//|   M5 tier  -> InpTPPipsM5 (default 60 pips = 4000.00 -> 4006.00) |
//|   M15, M30, H1, H4 -> no target, exactly as the parent           |
//|                                                                  |
//| PIP SIZE: one pip is the GOLD convention, 0.10 of price. The two  |
//| defaults above are therefore a 3.00 target on M2 and a 6.00       |
//| target on M5, whatever the feed's digit count. In points — the    |
//| unit MT5 itself works in — that resolves as:                      |
//|                                                                  |
//|   feed             1 point   pts/pip   M2 (30p)    M5 (60p)      |
//|   2-decimal gold    0.01       10      300 pts     600 pts       |
//|   3-decimal gold    0.001     100     3000 pts    6000 pts       |
//|                                                                  |
//| InpPipPoints = 0 (the default) AUTO-RESOLVES that from            |
//| SYMBOL_DIGITS, so moving between a 2- and a 3-decimal gold feed   |
//| cannot silently move every target by a factor of ten. A positive  |
//| InpPipPoints overrides it and is taken literally — which is what  |
//| a non-gold symbol needs, since AUTO would make a pip 0.10 of      |
//| price there too (1000 pips on 5-digit FX): set InpPipPoints = 10  |
//| for a 5-digit FX pair. OnInit prints the resolved points-per-pip  |
//| and the resulting price distance per symbol, so the figure is     |
//| visible rather than assumed.                                     |
//|                                                                  |
//| THE TARGET IS ADDITIVE, NOT A REPLACEMENT. The kumo-touch exit,   |
//| the rejection-candle exit, the BE stop, the chandelier trail and  |
//| the disaster stop ALL still run on M2 and M5, unchanged. The      |
//| trade ends on whichever arrives first. So the only behavioural    |
//| change is that an M2/M5 trade which would have run past           |
//| InpTPPipsM2/M5 of profit is now cut there instead of being        |
//| handed to the trail — this build can shorten those trades, never  |
//| extend them. Set InpHardTPEnabled = false to get the parent back  |
//| exactly.                                                         |
//|                                                                  |
//| ANCHORING AND SELF-HEAL. The target is measured from the ENTRY    |
//| price, not the current quote, so it never drifts. Two details     |
//| make that hold in practice:                                      |
//|   * Every PositionModify in ManageLevelProtection now carries the |
//|     current TP back in. The parent passed a bare 0 in that slot,  |
//|     which was right when no tier had a target but would have      |
//|     STRIPPED the target the first time BE or the trail fired.     |
//|   * A target that is missing — rejected at send time by the       |
//|     broker's minimum stop distance, or stripped later — is        |
//|     re-attached on the next minute from the same entry anchor,    |
//|     mirroring the disaster stop's R3 self-heal. After a restart   |
//|     SyncStateFromPositions restores entryPrice from               |
//|     POSITION_PRICE_OPEN, so the re-attached target lands where it |
//|     would have at open.                                          |
//| A TP fill needs no bookkeeping of its own: SyncStateFromPositions |
//| rebuilds every level's state from the live positions each minute, |
//| so a broker-side close frees the tier on the next bar.            |
//|                                                                  |
//| NOTE ON SIZING: risk sizing is UNCHANGED and still runs off       |
//| ATR x InpRiskATRMult with the disaster stop at ATR x              |
//| InpDisasterATRMult. The target is a fixed pip distance while the  |
//| stop is volatility-scaled, so the effective reward:risk of an     |
//| M2/M5 trade MOVES WITH VOLATILITY — 120 pips is a long way in a   |
//| quiet session and a short one in a fast session. That is inherent |
//| to mixing a fixed target with an ATR stop; judge the two tiers'   |
//| results against the parent's before reading anything into them.   |
//|                                                                  |
//|------------------------------------------------------------------|
//| INHERITED FROM THE PARENT, UNCHANGED:                            |
//+------------------------------------------------------------------+
//| A fork of the live VPS build (ichimoku-h4-m1-vps-ea.mq5, magic    |
//| 20260858). THE FIVE LIVE TIERS ARE UNCHANGED — same chains, same  |
//| cloud gate, same H4/H1 bias ladder, same D1 filter on H4, same    |
//| exits, same risk ladder, same robustness pack R2-R6.              |
//| EXPERIMENTAL CHANGE — one new tradable tier at the BOTTOM:        |
//|   * CHAIN: M1 + M2 aligned, and nothing else. That is the whole   |
//|     entry condition — the scalp tier reads no higher timeframe    |
//|     for alignment. M1 alone still never trades.                   |
//|   * BIAS: M30. This tier answers to M30 ALONE — the same          |
//|     price+chikou alignment test every timeframe M1..D1 uses,      |
//|     applied to M30. It deliberately does NOT consult H4 and does  |
//|     not use the H1 stand-in ladder, so the scalp tier can trade   |
//|     while H4 is flat AND can trade against an aligned H4 (a       |
//|     counter-trend scalp is intentional here, not a bug). Set      |
//|     InpM30ScalpBias = false to drop the gate — the tier then     |
//|     trades on the M1+M2 chain alone.                              |
//|   * M2 IS NOT A RUNG: the five live tiers keep their exact        |
//|     chains, so M5 is still M1 + M5, NOT M1 + M2 + M5.             |
//|     ChainAligned() walks up from M1 and skips the M2 rung for     |
//|     every tier above the scalp tier, so the live tiers' trade set |
//|     is what the VPS build produces and everything this fork adds  |
//|     is strictly additional M2-tier trades.                        |
//|   * The scalp tier is level 0 of the stack, so the existing         |
//|     consolidation rule handles it with no special case: the       |
//|     entry scan runs highest-tier-first, so any of the five live   |
//|     tiers that aligns on the same minute SUPERSEDES the scalp     |
//|     trade. The scalp tier therefore opens only when M1+M2 align   |
//|     and no live tier passes its gates on that same minute — its   |
//|     contribution is the trades the stack previously declined, not |
//|     a doubling of the count.                                      |
//|   * ONE-POSITION RULE, AND WHERE IT IS ENFORCED. The scan SKIPS a |
//|     tier that already holds a position instead of evaluating it,  |
//|     and the supersede loop only walks BELOW the tier that opens   |
//|     (`l < topTier`) — so a tier that is already running neither   |
//|     blocks a new entry nor gets closed by one. For the five live  |
//|     tiers that is the parent's behaviour, kept as-is. For the     |
//|     scalp tier it is a NEW hazard, because M30 rather than H4     |
//|     grants its direction: with an H4 long already running, M1+M2  |
//|     can align SHORT on a later bar, and the scalp would open      |
//|     against the live position — on a netting account MT5 would    |
//|     then net the two together, shrinking or closing the live     |
//|     trade behind the EA's back. OtherLevelBusy() closes that hole |
//|     for the bottom tiers (InpScalpNeedsFlatSymbol, default on;    |
//|     see the note at the top of this file — it now covers M1 too). |
//|     The parent's equivalent case among the five live tiers        |
//|     is deliberately NOT changed here, to keep their behaviour     |
//|     identical — so "at most one position per symbol" holds for    |
//|     the bottom tiers, but remains as loose for the live tiers as  |
//|     is in the parent.                                             |
//| LEVEL RENUMBERING — the trap this fork had to survive. Adding a   |
//| tier at the bottom renumbered all five existing levels (M5 0->1,  |
//| M15 1->2, M30 2->3, H1 3->4, H4 4->5), so every site that         |
//| hardcoded a level number moved with it. Four were live here:      |
//|   * LevelRiskPct() — M2 row added, five cases shifted. Left alone |
//|     every tier would have been sized with the row below it (H4    |
//|     risking H1's 10% instead of 20%).                             |
//|   * LevelCloudBiasOK() — the "sits on M1, so it carries the full  |
//|     current+future check" case was lvl == 0, which is now M2.     |
//|     Both M2 AND M5 need that M1 full check: M2 because M1 is the  |
//|     rung below it, M5 because M2 is NOT its rung.                 |
//|   * ManageLevelProtection() — the BE/chandelier bucket split on   |
//|     lvl >= 3, where 3 was H1. After the shift 3 is M30, so M30    |
//|     would have taken the H1/H4 tighter arming rule and H1 would   |
//|     have lost it. Now lvl >= LVL_H1.                              |
//|   * ENUM_H1_BIAS_TIER — the enum values ARE level indices, so the |
//|     ceiling moved from {0,1,2,3} to {1,2,3,4}.                    |
//| The M1-strict cloud-bias logic this forks is otherwise unchanged  |
//| (promoted 2026-08-20 from the most profitable cloud-bias          |
//| experiment, user report 2026-08-20; $100 -> $14000 on Jan-Aug     |
//| 2026 data), as is the ROBUSTNESS PACK (recommendations R2-R6,     |
//| promoted 2026-08-23).                                             |
//| The cloud-bias gate (Span A vs Span B) requires M1 to be twisted  |
//| the trade's way at BOTH the current bar (last closed bar) and the |
//| far end of the future cloud (Kijun bars ahead) — the full check.  |
//| On M2 and above the CURRENT cloud may be any value, bullish or    |
//| bearish; only the FUTURE cloud must be in the trade's direction.  |
//| DIFFERENT MODEL: the top-down builds required every timeframe     |
//| from the anchor down to M1 to agree before a single trade could   |
//| open. This build is BOTTOM-UP — the stack is grown upward from    |
//| M1 and each tier trades its own chain — with DIRECTION granted    |
//| by a bias timeframe (H4 primary, H1 stand-in) instead of by       |
//| top-down agreement.                                               |
//| Entry: per-TF alignment (price + chikou above/below tenkan,       |
//|        kijun and cloud), checked BOTTOM-UP: a tier opens only     |
//|        when the full stack M1..tier TF is aligned in one          |
//|        direction:                                                 |
//|          Tier M2 : M1 + M2 aligned              -> open trade     |
//|          Tier M5 : M1 + M5 aligned              -> open trade     |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade     |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade     |
//|          Tier H1 : M1 ... H1 aligned            -> open trade     |
//|          Tier H4 : M1 ... H4 aligned            -> open trade     |
//|        M1 alone never trades — it is only the start of the stack. |
//|        The cloud bias gate (Span A vs Span B) applies to the tier |
//|        TF and the TF directly below it: M1 must be twisted the     |
//|        trade's way at both the current bar and the far end of the |
//|        future cloud; M2 and above need only the far end — the     |
//|        current cloud may be either direction. H4 is the bias for  |
//|        the five live tiers (H4 bullish -> buys only, bearish ->   |
//|        sells only, flat -> no trades), and the H4 tier itself is  |
//|        also gated by the D1 bias: D1 bullish -> only H4 buys, D1  |
//|        bearish -> only H4 sells, D1 in the cloud -> no H4 trades. |
//|        The M2 scalp tier is outside that ladder entirely — its    |
//|        bias is M30 (see InpM30ScalpBias above).                   |
//|        H1 BIAS: an unaligned H4 would otherwise freeze the whole  |
//|        stack, including M5. The lower tiers get a second, smaller |
//|        bias to fall back on: when H4 carries no direction, a tier |
//|        at or below InpH1BiasMaxTier may open provided H1 itself   |
//|        is aligned (same price+chikou test) with the trade. H4     |
//|        aligned WITH the trade is still the primary path; H4       |
//|        aligned AGAINST the trade stays blocked unless             |
//|        InpH1BiasMode = H1BIAS_ALWAYS. The H4 tier never uses the  |
//|        stand-in, and the D1 filter on the H4 tier is untouched.   |
//| Exit:  price TOUCHES the level TF's cloud edge (no wait for a  |
//|        candle close inside the kumo). A long exits when the bid |
//|        touches the cloud's upper edge; a short when the ask     |
//|        touches the lower edge. A very strong REJECTION candle   |
//|        against the trade also closes it (sweeps the recent      |
//|        swing extreme of InpRejSwingBars bars, wick >=           |
//|        InpRejWickPct of the range, close in the outer           |
//|        InpRejClosePct — all four conditions must hold). No      |
//|        entry stop loss in this build — the trade runs until an |
//|        exit, with the profit protection layer taking over once  |
//|        it turns green:                                          |
//|          Break-even   : profit >= ATR threshold (tighter for the  |
//|                         H1/H4 levels) -> SL to entry + cover      |
//|          Chandelier   : H1/H4 levels trail the stop behind the    |
//|                         peak once profitable (InpTrailActivateATR);|
//|                         M2/M5/M15/M30 keep the spike-gated trail  |
//|                         (InpSpikeLockATR), only ever tightening   |
//|        ATR comes from each level's own TF — so the scalp tier is  |
//|        protected on M2's ATR, and its disaster stop is 8 x that.  |
//| Risk:  single position per level per symbol, but consolidation:   |
//|        when several tiers align at once only the LARGEST opens,   |
//|        and any smaller tier already running on the symbol is      |
//|        closed first. Every trade risks a fixed % of the ACTUAL    |
//|        equity at entry, de-risking as the account grows: tier 1   |
//|        below $7000 (M2 0.5%, M5/M15 1%, M30 5%, H1 10%, H4 20%),  |
//|        tier 2 half regime $7000-$13000 (0.25/0.5/0.5/2.5/5/10),   |
//|        tier 3 tiny regime $13000+ (0.05/0.1/0.1/0.2/1/2), against |
//|        the reference distance ATR(level TF) x InpRiskATRMult      |
//|        (sizing basis only — no entry stop is attached there). No  |
//|        multipliers, no streak compounding. These are SIZING       |
//|        percentages, not the money at risk: the disaster stop sits |
//|        at ATR x InpDisasterATRMult (8) while sizing uses x2, so a |
//|        stop-out costs about FOUR TIMES the figure above (tier 1   |
//|        H4 = 20% sizing, ~80% at the stop). OnInit prints the      |
//|        resolved ladder and that real figure.                      |
//|        The scalp tier carries a SMALLER RISK BUDGET than M5 (0.5% |
//|        vs 1% in tier 1, 2% vs 4% at the stop) because a 2-minute  |
//|        bar sits near the noise floor on a wide-spread feed and a  |
//|        wrong M2 read costs the same dollars per lot as a wrong M5 |
//|        read. Note this is a budget, NOT a lot count: lots scale as|
//|        riskPct / ATR(tier TF), and ATR(M2) < ATR(M5), so the      |
//|        scalp tier's LOT SIZE is frequently LARGER than M5's. The   |
//|        dollars at the disaster stop are what stays smaller.        |
//| VPS:   no Alert() popups and no equity alert — every entry/exit   |
//|        sends a SendNotification push and a journal Print, and all |
//|        logic runs only on closed M1 bars (once per minute) to     |
//|        keep CPU/network use on a cheap VPS negligible. The        |
//|        desktop counterpart ichimoku-h4-m1-mt5pc-ea.mq5 restores   |
//|        the popups and the weekly equity reminder.                 |
//| Magic: 20260870 — fresh, shared with nothing. The parent VPS build |
//|        runs 20260858, its desktop twin 20260860, so this fork can  |
//|        run side by side with the live build on the same account    |
//|        without either one adopting the other's positions.         |
//|                                                                  |
//| ROBUSTNESS PACK (live since 2026-08-23) — five hardening changes |
//| (review recommendations R2-R6), promoted verbatim from the       |
//| robustness experimental fork.                                    |
//|   R2 UNKNOWN-POSITION GUARD: a magic-matching position whose     |
//|      comment no longer names a level (brokers may rewrite or     |
//|      truncate comments on partial fills / server events) used to |
//|      be invisible — orphaned from BE/trail/cloud exits while the |
//|      EA opened duplicates behind it. It is now logged once per   |
//|      ticket and BLOCKS new entries on that symbol until it is    |
//|      gone. Exits/protection for known levels still run.          |
//|   R3 DISASTER STOP: every entry carries a wide hard SL of        |
//|      ATR(level TF) x InpDisasterATRMult (default 8) so a gap or  |
//|      a dead VPS/link cannot run unbounded. Break-even and the    |
//|      chandelier still take over once green; a missing stop       |
//|      self-heals in ManageLevelProtection().                      |
//|   R4 PEAK REBUILD: after a restart mid-trade the chandelier      |
//|      references are rebuilt from level-TF history since the      |
//|      position's open time instead of collapsing to the open      |
//|      price (which left the trail far looser than before).        |
//|   R5 ORDER ROBUSTNESS: SetTypeFillingBySymbol() before every     |
//|      order (the FOK default breaks on IOC-only brokers), and     |
//|      the margin cap commits at most InpMarginUsePct % (default   |
//|      80) of free margin per order instead of 100%.               |
//|   R6 TWIN RULE: the desktop build ichimoku-h4-m1-mt5pc-ea.mq5    |
//|      carries this exact pack; the only intended differences are  |
//|      the magic number, the Alert() popups and the weekly equity  |
//|      reminder (see AGENTS.md). Deliberately NOT implemented      |
//|      (user decision): recommendation R1, the supersede invariant |
//|      guard that would abort a new entry while an existing        |
//|      higher-tier position survives its close attempt.            |
//| Magic: 20260870 — fresh, shared with nothing (see above).        |
//|        This is an EXPERIMENTAL fork, not a promoted build, so it  |
//|        has no desktop twin: the R6 twin rule below still binds    |
//|        the two production builds to each other, not this file.    |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Risk Management (per level, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(level TF) x this (risk sizing basis)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to band 2
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to band 3
input double InpRiskTier4At     = 17000.0;// Equity where risk drops to band 4
input double InpRiskTier5At     = 20000.0;// Equity where risk drops to band 5 (the top band)
//--- Band 1 — equity < InpRiskTier2At. H4 anchors the band; every other
//--- tier is a fixed fraction of it (M1 .0125, M2 .025, M5/M15 .05,
//--- M30 .25, H1 .5), the shape bands 1 and 2 have always used.
input double InpRiskPctM1       = 0.25;   // M1   — band 1 — the new M1 tier, sized at half the M2 scalp
input double InpRiskPctM2       = 0.5;    // M2   — band 1 — the scalp tier, sized below M5
input double InpRiskPctM5       = 1.0;    // M5   — band 1
input double InpRiskPctM15      = 1.0;    // M15  — band 1
input double InpRiskPctM30      = 5.0;    // M30  — band 1
input double InpRiskPctH1       = 10.0;   // H1   — band 1
input double InpRiskPctH4       = 20.0;   // H4   — band 1 (anchor)
//--- Band 2 — InpRiskTier2At .. InpRiskTier3At. Unchanged from the parent.
input double InpRiskPctM1_T2    = 0.125;  // M1   — band 2
input double InpRiskPctM2_T2    = 0.25;   // M2   — band 2
input double InpRiskPctM5_T2    = 0.5;    // M5   — band 2
input double InpRiskPctM15_T2   = 0.5;    // M15  — band 2
input double InpRiskPctM30_T2   = 2.5;    // M30  — band 2
input double InpRiskPctH1_T2    = 5.0;    // H1   — band 2
input double InpRiskPctH4_T2    = 10.0;   // H4   — band 2 (anchor)
//--- Band 3 — InpRiskTier3At .. InpRiskTier4At. RAISED WELL PAST the
//--- parent's 2.0: at H4 7.0 the 13k floor risks MORE money than the 7k
//--- floor ($1,718 vs $1,321), so 13000 is now a risk STEP-UP, not a
//--- de-risking point. Deliberate — see the header table.
input double InpRiskPctM1_T3    = 0.0875; // M1   — band 3
input double InpRiskPctM2_T3    = 0.175;  // M2   — band 3
input double InpRiskPctM5_T3    = 0.35;   // M5   — band 3
input double InpRiskPctM15_T3   = 0.35;   // M15  — band 3
input double InpRiskPctM30_T3   = 1.75;   // M30  — band 3 (parent had 0.2 — see the header note on M30's ratio)
input double InpRiskPctH1_T3    = 3.5;    // H1   — band 3
input double InpRiskPctH4_T3    = 7.0;    // H4   — band 3 (anchor)
//--- Band 4 — InpRiskTier4At .. InpRiskTier5At. New.
input double InpRiskPctM1_T4    = 0.05;   // M1   — band 4
input double InpRiskPctM2_T4    = 0.1;    // M2   — band 4
input double InpRiskPctM5_T4    = 0.2;    // M5   — band 4
input double InpRiskPctM15_T4   = 0.2;    // M15  — band 4
input double InpRiskPctM30_T4   = 1.0;    // M30  — band 4
input double InpRiskPctH1_T4    = 2.0;    // H1   — band 4
input double InpRiskPctH4_T4    = 4.0;    // H4   — band 4 (anchor)
//--- Band 5 — InpRiskTier5At and above. The most conservative band in
//--- the file, though H4 2.0 merely MATCHES the parent's old 13000+
//--- figure rather than going below it.
input double InpRiskPctM1_T5    = 0.025;  // M1   — band 5
input double InpRiskPctM2_T5    = 0.05;   // M2   — band 5
input double InpRiskPctM5_T5    = 0.1;    // M5   — band 5
input double InpRiskPctM15_T5   = 0.1;    // M15  — band 5
input double InpRiskPctM30_T5   = 0.5;    // M30  — band 5
input double InpRiskPctH1_T5    = 1.0;    // H1   — band 5
input double InpRiskPctH4_T5    = 2.0;    // H4   — band 5 (anchor)
input double InpMarginUsePct     = 80.0;   // Max % of FREE margin one order may commit (R5; parent used 100%)

// H1 stand-in bias mode — what the lower tiers may do when the H4 bias
// does not carry the trade.
//   H1BIAS_OFF     : no stand-in; H4 governs every tier on its own
//   H1BIAS_FLAT_H4 : stand-in allowed only while H4 is FLAT (unaligned /
//                    in its cloud) — never against an aligned H4
//   H1BIAS_ALWAYS  : stand-in allowed even when H4 is aligned the OTHER
//                    way (counter-H4 trading on the lower tiers)
enum ENUM_H1_BIAS_MODE { H1BIAS_OFF = 0, H1BIAS_FLAT_H4 = 1, H1BIAS_ALWAYS = 2 };

// Highest tier permitted to enter on the H1 stand-in bias. The H4 tier is
// deliberately absent — it always needs H4 (and D1) itself.
// The enum values ARE level indices, so inserting the M2 scalp tier at the
// bottom of the stack moved every one of them up by one: the ceiling is now
// {1=M5, 2=M15, 3=M30, 4=H1} where it used to be {0=M5, 1=M15, 2=M30,
// 3=H1}. Left unshifted, the default H1TIER_M30 would have allowed only up
// to M15 on the H1 stand-in and silently dropped the M30 tier from it.
// The M2 scalp tier is deliberately NOT named here: it sits below every
// setting, and it does not use this ladder at all (its bias is M30).
enum ENUM_H1_BIAS_TIER { H1TIER_M5 = 2, H1TIER_M15 = 3, H1TIER_M30 = 4, H1TIER_H1 = 5 };

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias: M1 current+future must agree; M2+ future cloud only
input bool   InpH4Bias           = true;   // H4 is the bias — tiers trade in H4's direction (H4 flat = no trades unless the H1 bias stands in)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "M2 Scalp Tier (M1+M2 chain, M30 bias)"
input bool   InpM2ScalpTier  = true;       // Let M1 + M2 aligned open an M2 scalp trade, with its own risk row and exits
input bool   InpM30ScalpBias = true;       // Require M30 alignment for the M2 scalp tier (its ONLY bias — H4/H1 are not consulted). Off = M1+M2 chain alone
input bool   InpM1Tier       = true;       // TIER: let M1 ALONE open a trade (level 0). Off = the parent's stack, where M1 is only the start of every chain
input bool   InpM1M30Bias    = true;       // Require M30 alignment for the M1 tier (its ONLY bias, same rule as the M2 scalp). Off = bare M1 alignment
input bool   InpScalpNeedsFlatSymbol = true; // Never open M1 or M2 while ANY other tier holds a position (keeps the one-position-per-symbol rule; see the note above it)
input bool   InpM2CloudFull  = false;      // M2's OWN cloud: true = M1-style FULL check (current AND future), false = the M5+ future-only rule

input group  "H1 Bias (lets the live tiers trade when H4 is flat)"
input ENUM_H1_BIAS_MODE InpH1BiasMode    = H1BIAS_FLAT_H4; // 0=off (H4 only), 1=stand in only while H4 is flat, 2=stand in even against an aligned H4
input ENUM_H1_BIAS_TIER InpH1BiasMaxTier = H1TIER_M30;     // Highest tier allowed to enter on the H1 bias (2=M5, 3=M15, 4=M30, 5=H1; the M1 and M2 tiers never use it — they answer to M30)
input bool   InpH1BiasCloudCheck = true;   // Also require the H1 cloud (Span A vs Span B) to carry the trade's bias

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M2/M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M2/M5/M15/M30 spike lock)
input double InpTrailActivateATR  = 0.5;   // H1/H4 chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR (level TF)

input group  "Disaster Stop (hard tail-risk stop)"
input bool   InpDisasterStopEnabled = true;   // Attach a wide hard SL at entry (bounds gap/disconnect loss)
input double InpDisasterATRMult     = 8.0;    // Disaster stop distance = ATR(level TF) x this

input group  "Hard Take Profit (M2 + M5 only — attached at entry, in pips)"
input bool   InpHardTPEnabled = true;    // Attach a broker-side TP to M2/M5 entries (M15/M30/H1/H4 never get one)
input double InpPipPoints     = 0.0;     // Points per pip. 0 = AUTO (gold convention: 1 pip = 0.10 of price, so 10 pts on a 2-decimal feed, 100 on a 3-decimal one). Set explicitly for a non-gold symbol.
input double InpTPPipsM1      = 30.0;    // M1 tier take profit, pips — 30 = 4000.00 -> 4003.00 (0 = no TP on this tier)
input double InpTPPipsM2      = 40.0;    // M2 scalp tier take profit, pips — 40 = 4000.00 -> 4004.00 (0 = no TP on this tier)
input double InpTPPipsM5      = 50.0;    // M5 tier take profit, pips — 50 = 4000.00 -> 4005.00 (0 = no TP on this tier)

input group  "Hard Stop Loss (M1 + M2 + M5 only — attached at entry, in pips)"
input bool   InpHardSLEnabled = true;    // Give M1/M2/M5 a tight hard SL instead of the wide 8xATR disaster stop
input double InpSLPipsM1      = 20.0;    // M1 tier stop, pips — 20 against a 30-pip target = 1.50 : 1
input double InpSLPipsM2      = 25.0;    // M2 tier stop, pips — 25 against a 40-pip target = 1.60 : 1
input double InpSLPipsM5      = 30.0;    // M5 tier stop, pips — 30 against a 50-pip target = 1.67 : 1

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close a trade when a very strong rejection candle forms against it on the tier TF
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   7      // tradable levels: M1, M2 (scalp), M5, M15, M30, H1, H4 — one per stack TF
#define TFS      7      // stack: M1, M2, M5, M15, M30, H1, H4
#define IDX_M1   0      // index of M1 in tfs[] — the start of every chain
#define IDX_M2   1      // index of M2 in tfs[] — the scalp tier's own TF, and NOT a rung
#define IDX_M5   2      // index of M5 in tfs[] — the first of the five live tiers (documentation only: no call site indexes M5 by name)
#define IDX_M30  4      // index of M30 in tfs[] — the scalp tier's bias TF
#define IDX_H1   5      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   6      // index of H4 in tfs[] — the primary bias TF

// Tradable LEVEL indices into state[]/atr[]/entryPrice[]/peak*/beMoved[],
// lowest tier first. The scalp tier had to go at the BOTTOM (level 0) so
// that the existing consolidation rule — entry scan highest-tier-first,
// lower tiers closed when a higher one opens — supersedes it with no
// special case, and so that "lvl + 1" still names the tier's TF.
#define LVL_M1   0      // the NEW M1 tier — chain M1 alone, bias M30
#define LVL_M2   1      // the M2 scalp tier — chain M1 + M2, bias M30  (was 0)
#define LVL_M5   2      // first of the five live tiers (was 1)
#define LVL_M15  3      // (was 2)
#define LVL_M30  4      // (was 3)
#define LVL_H1   5      // (was 4) — the BE/chandelier bucket boundary
#define LVL_H4   6      // (was 5) — the top tier, still LEVELS - 1

// With M1 tradable, the level list {M1,M2,M5,M15,M30,H1,H4} is exactly
// tfs[], so a level index IS its own tf index and the parent's "lvl + 1"
// offset is gone. LVL_* and IDX_* are now equal by construction; both are
// kept because they say different things at a call site — which TIER, or
// which TIMEFRAME.

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M2", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];       // ATR(level TF) — BE and spike-lock trail sizing
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)

// R2: unknown-position guard. A position carrying our magic whose comment
// no longer names a level cannot be managed (no BE/trail/cloud exit can
// find it) — track it, block new entries on its symbol until it is gone,
// and log it once per ticket (not once per minute).
bool              symBlockedUnknown[MAX_SYMS];
ulong             unknownLoggedTickets[64];
int               unknownLoggedCount   = 0;

// M2 scalp tier readiness, per symbol. A feed that refuses the M2 ichimoku
// or M2 ATR handle must NOT be fatal: the five live tiers have nothing to do
// with M2 and must keep running. scalpReady=false disables the scalp tier for
// that symbol only. scalpReported makes the startup read-out fire once, on the
// first tick where M2 is actually readable — deciding it in OnInit() would
// report "no history" for a healthy feed whose M2 series has not been built
// yet, which is the one thing this diagnostic must not get wrong.
bool              scalpReady[MAX_SYMS];
bool              scalpReported[MAX_SYMS];

int MAGIC = 20260872;   // M1 tier + M2 scalp, hard M1/M2/M5 TP, 5-band risk — fork of 20260871

CTrade trade;

//==============================================================
// Initialization and Deinitialization
//==============================================================

int ParseSymbols(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   int cnt = 0;
   for(int i = 0; i < n && cnt < MAX_SYMS; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;
      bool dup = false;
      for(int j = 0; j < cnt; j++)
         if(syms[j] == sym) { dup = true; break; }
      if(dup) continue;
      if(SymbolSelect(sym, true)) syms[cnt++] = sym;
   }
   return cnt;
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   // A bad pip size would silently misplace every target, so refuse to
   // start rather than trade a target nobody intended. Negative pip counts
   // are the same class of error; 0 is legitimate and means "no TP here".
   if(InpHardTPEnabled)
   {
      // 0 is legal and means AUTO; only a negative override is an error.
      if(InpPipPoints < 0.0)
      {
         Print("Hard TP: InpPipPoints cannot be negative (0 = auto) — got " +
               DoubleToString(InpPipPoints, 2) + ". Aborting.");
         return(INIT_FAILED);
      }
      if(InpTPPipsM1 < 0.0 || InpTPPipsM2 < 0.0 || InpTPPipsM5 < 0.0)
      {
         Print("Hard TP: InpTPPipsM1/M2/M5 cannot be negative. Aborting.");
         return(INIT_FAILED);
      }
   }

   if(InpHardSLEnabled)
   {
      if(InpSLPipsM1 < 0.0 || InpSLPipsM2 < 0.0 || InpSLPipsM5 < 0.0)
      {
         Print("Hard SL: InpSLPipsM1/M2/M5 cannot be negative. Aborting.");
         return(INIT_FAILED);
      }
      // A stop at or beyond the target is almost certainly a typo, and it
      // would size the tier as if it risked far less than it can lose.
      if((InpSLPipsM1 > 0.0 && InpTPPipsM1 > 0.0 && InpSLPipsM1 >= InpTPPipsM1) ||
         (InpSLPipsM2 > 0.0 && InpTPPipsM2 > 0.0 && InpSLPipsM2 >= InpTPPipsM2) ||
         (InpSLPipsM5 > 0.0 && InpTPPipsM5 > 0.0 && InpSLPipsM5 >= InpTPPipsM5))
         Print(PCTime() + " | !! HARD SL >= HARD TP on at least one of M1/M2/M5 — reward:risk is "
               "below 1:1 there. Intentional? If not, check InpSLPips*/InpTPPips*.");
   }

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      symBlockedUnknown[s] = false;
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
      }

      // M2 handles are created like every other TF's, but a FAILURE here must
      // not abort OnInit: the M2 scalp tier is an addition, and a feed that
      // refuses M2 must still leave the five live tiers running. Without the
      // t != IDX_M2 exemption this loop would kill the whole EA on such a
      // feed — including the live tiers — with nothing printed, because the
      // read-out below would never be reached.
      scalpReady[s]    = InpM2ScalpTier;
      scalpReported[s] = false;
      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE)
         {
            if(t == IDX_M2) { scalpReady[s] = false; continue; }   // M2 not carried by this feed
            return(INIT_FAILED);
         }
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[l], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE)
         {
            if(l == LVL_M2) { scalpReady[s] = false; continue; }   // M2 ATR not carried by this feed
            return(INIT_FAILED);
         }
      }

      // Report the scalp tier's availability now, and say plainly what is
      // lost. A symbol without a usable M2 feed keeps every live tier; only
      // the scalp tier goes dark, and it must be obvious which of the two
      // happened rather than the tier merely looking filtered. Guarded on
      // InpM2ScalpTier so switching the tier off does not masquerade as a
      // refused M2 feed — a false alarm in the one diagnostic whose whole
      // job is telling "off" apart from "starved".
      if(InpM2ScalpTier && !scalpReady[s])
         Print(PCTime() + " | " + syms[s] + " has NO usable M2 feed (handle refused) — the M2 SCALP TIER IS "
               "DISABLED on this symbol. The five live tiers are unaffected and keep trading.");
   }

   //--- Risk-ladder read-out. The % named in the inputs is the SIZING basis,
   //--- not the money at risk: the disaster stop sits at a different ATR
   //--- multiple, so a stop-out costs about four times the figure. State the
   //--- resolved ladder and this account's real exposure once, at startup,
   //--- rather than leaving it to be inferred from the input list.
   if(!(InpRiskTier2At < InpRiskTier3At &&
        InpRiskTier3At < InpRiskTier4At &&
        InpRiskTier4At < InpRiskTier5At))
      Print(PCTime() + " | !! RISK BAND EDGES ARE NOT ASCENDING (Tier2At < Tier3At < Tier4At < "
            "Tier5At is required). At least one band is unreachable — fix the inputs.");

   PrintFormat("%s | Risk ladder (%% of equity; x%.1f = money at the %.0fxATR disaster stop)",
               PCTime(), InpDisasterATRMult / InpRiskATRMult, InpDisasterATRMult);
   PrintFormat("   band  equity range              M1      M2      M5      M15     M30     H1      H4     TOTAL");
   PrintFormat("   1     below %-9.0f       %6.4f  %6.3f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f",
               InpRiskTier2At, InpRiskPctM1, InpRiskPctM2, InpRiskPctM5, InpRiskPctM15,
               InpRiskPctM30, InpRiskPctH1, InpRiskPctH4,
               InpRiskPctM1 + InpRiskPctM2 + InpRiskPctM5 + InpRiskPctM15 + InpRiskPctM30 + InpRiskPctH1 + InpRiskPctH4);
   PrintFormat("   2     %-6.0f .. %-9.0f  %6.4f  %6.3f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f",
               InpRiskTier2At, InpRiskTier3At, InpRiskPctM1_T2, InpRiskPctM2_T2, InpRiskPctM5_T2, InpRiskPctM15_T2,
               InpRiskPctM30_T2, InpRiskPctH1_T2, InpRiskPctH4_T2,
               InpRiskPctM1_T2 + InpRiskPctM2_T2 + InpRiskPctM5_T2 + InpRiskPctM15_T2 + InpRiskPctM30_T2 + InpRiskPctH1_T2 + InpRiskPctH4_T2);
   PrintFormat("   3     %-6.0f .. %-9.0f  %6.4f  %6.3f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f",
               InpRiskTier3At, InpRiskTier4At, InpRiskPctM1_T3, InpRiskPctM2_T3, InpRiskPctM5_T3, InpRiskPctM15_T3,
               InpRiskPctM30_T3, InpRiskPctH1_T3, InpRiskPctH4_T3,
               InpRiskPctM1_T3 + InpRiskPctM2_T3 + InpRiskPctM5_T3 + InpRiskPctM15_T3 + InpRiskPctM30_T3 + InpRiskPctH1_T3 + InpRiskPctH4_T3);
   PrintFormat("   4     %-6.0f .. %-9.0f  %6.4f  %6.3f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f",
               InpRiskTier4At, InpRiskTier5At, InpRiskPctM1_T4, InpRiskPctM2_T4, InpRiskPctM5_T4, InpRiskPctM15_T4,
               InpRiskPctM30_T4, InpRiskPctH1_T4, InpRiskPctH4_T4,
               InpRiskPctM1_T4 + InpRiskPctM2_T4 + InpRiskPctM5_T4 + InpRiskPctM15_T4 + InpRiskPctM30_T4 + InpRiskPctH1_T4 + InpRiskPctH4_T4);
   PrintFormat("   5     %-6.0f and above     %6.4f  %6.3f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f  %6.2f",
               InpRiskTier5At, InpRiskPctM1_T5, InpRiskPctM2_T5, InpRiskPctM5_T5, InpRiskPctM15_T5,
               InpRiskPctM30_T5, InpRiskPctH1_T5, InpRiskPctH4_T5,
               InpRiskPctM1_T5 + InpRiskPctM2_T5 + InpRiskPctM5_T5 + InpRiskPctM15_T5 + InpRiskPctM30_T5 + InpRiskPctH1_T5 + InpRiskPctH4_T5);
   PrintFormat("   ACTIVE at equity %.2f -> M1 %.4f%% (~%.3f%% at stop), M2 %.3f%% (~%.2f%%), M5 %.2f%% (~%.2f%%), H4 %.2f%% (~%.2f%%)",
               AccountInfoDouble(ACCOUNT_EQUITY),
               LevelRiskPct(LVL_M1), LevelRiskPct(LVL_M1) * (InpDisasterATRMult / InpRiskATRMult),
               LevelRiskPct(LVL_M2), LevelRiskPct(LVL_M2) * (InpDisasterATRMult / InpRiskATRMult),
               LevelRiskPct(LVL_M5), LevelRiskPct(LVL_M5) * (InpDisasterATRMult / InpRiskATRMult),
               LevelRiskPct(LVL_H4), LevelRiskPct(LVL_H4) * (InpDisasterATRMult / InpRiskATRMult));

   //--- The pip size is the one number that silently ruins a fixed target
   //--- when the feed's digit count is not what was assumed, so resolve it
   //--- per symbol and state it in price units rather than leaving
   //--- "120 pips" to be trusted.
   if(InpHardTPEnabled)
   {
      for(int s = 0; s < symsCount; s++)
      {
         int    d    = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
         double pts  = PipPoints(s);
         double pp   = PipPrice(s);

         if(pts <= 0.0)
         {
            Print(PCTime() + " | !! Hard TP: " + syms[s] + " reports point size 0 — no target can be "
                  "sized on this feed. The tier still trades on its managed exits; set InpPipPoints "
                  "explicitly to restore the target.");
            continue;
         }

         // Points is the figure MT5 itself speaks in, so print it next to
         // the price distance the target actually lands at.
         PrintFormat("%s | Hard TP: %s (%d digits) — 1 pip = %.0f points = %s price | "
                     "M1 %.0f pips = %.0f points (%s) | M2 %.0f pips = %.0f points (%s) | "
                     "M5 %.0f pips = %.0f points (%s) | M15+ none%s",
                     PCTime(), syms[s], d, pts, DoubleToString(pp, d),
                     InpTPPipsM1, InpTPPipsM1 * pts, DoubleToString(InpTPPipsM1 * pp, d),
                     InpTPPipsM2, InpTPPipsM2 * pts, DoubleToString(InpTPPipsM2 * pp, d),
                     InpTPPipsM5, InpTPPipsM5 * pts, DoubleToString(InpTPPipsM5 * pp, d),
                     (InpPipPoints > 0.0 ? " [pip size: manual]" : " [pip size: auto]"));
      }
   }
   else
      Print(PCTime() + " | Hard TP: disabled — M1/M2/M5 run on managed exits only, as in the parent");

   //--- Stops, and the sizing consequence. Spelling out reward:risk here is
   //--- the cheapest place to catch a mis-set pip figure, and the 1x/4x split
   //--- is the single most misreadable thing about this build's risk table.
   if(InpHardSLEnabled)
   {
      PrintFormat("%s | Hard SL: M1 %.0f pips (R:R %.2f), M2 %.0f (%.2f), M5 %.0f (%.2f) — "
                  "clamped to the tighter of this and %.0fxATR; M15+ keep the disaster stop alone",
                  PCTime(),
                  InpSLPipsM1, (InpSLPipsM1 > 0 ? InpTPPipsM1 / InpSLPipsM1 : 0.0),
                  InpSLPipsM2, (InpSLPipsM2 > 0 ? InpTPPipsM2 / InpSLPipsM2 : 0.0),
                  InpSLPipsM5, (InpSLPipsM5 > 0 ? InpTPPipsM5 / InpSLPipsM5 : 0.0),
                  InpDisasterATRMult);
      Print(PCTime() + " | Hard SL: M1/M2/M5 are now SIZED ON THEIR REAL STOP, so a stop-out there "
            "costs ~1x the stated risk %. M15+ are still sized on " +
            DoubleToString(InpRiskATRMult, 1) + "xATR and stopped at " +
            DoubleToString(InpDisasterATRMult, 1) + "xATR, so a stop-out there still costs ~" +
            DoubleToString(InpDisasterATRMult / InpRiskATRMult, 0) + "x. Do not read the two halves "
            "of the risk ladder as one scale.");
   }
   else
      Print(PCTime() + " | Hard SL: disabled — every tier runs the wide disaster stop, as in the parent");

   //--- The M1 tier needs no readiness probe the way the M2 one does: M1 is
   //--- the base feed every chain already depends on, so if it were missing
   //--- the EA would have failed init above. State its configuration once.
   if(InpM1Tier)
      Print(PCTime() + " | M1 tier ACTIVE (chain: M1 ALONE — no higher TF confirms it; bias " +
            (InpM1M30Bias ? "M30" : "NONE — bare M1 alignment") + "; " +
            (InpScalpNeedsFlatSymbol ? "blocked while any other tier holds a position"
                                     : "!! NOT blocked by other open tiers — opposing entries may net") + ").");
   else
      Print(PCTime() + " | M1 tier OFF — M1 is only the start of every chain, as in the parent");

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(ichD1[s] != INVALID_HANDLE) IndicatorRelease(ichD1[s]);
      for(int l = 0; l < LEVELS; l++)
         if(atr[s][l] != INVALID_HANDLE) IndicatorRelease(atr[s][l]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl];
}

// R2: log an unparseable magic position once per ticket — without the
// ticket memory this would repeat every minute while the position lives.
// After 64 distinct tickets the log goes quiet but the block stays on.
void LogUnknownOnce(ulong ticket, string sym, string comm)
{
   for(int i = 0; i < unknownLoggedCount; i++)
      if(unknownLoggedTickets[i] == ticket) return;
   if(unknownLoggedCount < 64) unknownLoggedTickets[unknownLoggedCount++] = ticket;
   Print(PCTime() + " | !! " + sym + " position #" + IntegerToString((long)ticket) +
         " carries this EA's magic but its comment \"" + comm +
         "\" names no level — BE/trail/cloud exits CANNOT manage it." +
         " New entries on " + sym + " are blocked until it is closed.");
}

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15"). Entry/peak/BE memory is rebuilt for a
// restart mid-trade — the chandelier references from the level-TF history
// since the position opened (R4) — and cleared when the level is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
   {
      symBlockedUnknown[s] = false;              // R2: re-evaluated every sync
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         hasPos[s][l] = false;
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      string comm  = PositionGetString(POSITION_COMMENT);

      if(magic != MAGIC) continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;

         // R2: resolve the level from the comment; an unmatched comment on
         // a magic position means the identity is lost (broker rewrite,
         // partial fill suffix, manual tampering) — block the symbol.
         int lvlMatch = -1;
         for(int l = 0; l < LEVELS; l++)
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
            {
               lvlMatch = l;
               break;
            }

         if(lvlMatch < 0)
         {
            symBlockedUnknown[s] = true;
            LogUnknownOnce(ticket, sym, comm);
            continue;
         }

         state[s][lvlMatch] = dir;
         hasPos[s][lvlMatch] = true;

         // EA (re)started mid-trade — rebuild the protection references.
         // R4: peaks come from the level-TF bars since the position actually
         // opened, so the chandelier resumes where it left off instead of
         // restarting from the open price.
         if(entryPrice[s][lvlMatch] == 0.0)
         {
            entryPrice[s][lvlMatch] = PositionGetDouble(POSITION_PRICE_OPEN);
            double hi = entryPrice[s][lvlMatch];
            double lo = entryPrice[s][lvlMatch];
            MqlRates hist[];
            int nb = CopyRates(sym, tfs[lvlMatch + 1],
                               (datetime)PositionGetInteger(POSITION_TIME),
                               TimeCurrent(), hist);
            for(int b = 0; b < nb; b++)
            {
               if(hist[b].high > hi) hi = hist[b].high;
               if(hist[b].low  < lo) lo = hist[b].low;
            }
            peakHigh[s][lvlMatch] = hi;
            peakLow[s][lvlMatch]  = lo;
         }
         break;
      }
   }

   // Levels with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(!hasPos[s][l])
         {
            entryPrice[s][l] = 0.0;
            peakHigh[s][l]   = 0.0;
            peakLow[s][l]    = 0.0;
            beMoved[s][l]    = false;
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the H4 VPS build.
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open.
//
// The M2 scalp tier's chain ends AT M2 (topIdx == IDX_M2), so the
// guard below cannot fire for it — M2 is always required there.
// For every tier above it the guard DOES fire, which is exactly
// what keeps this fork's live chains identical to the VPS build's:
// M5 is still M1 + M5, NOT M1 + M2 + M5. M2 is a TIER here, not a
// rung. (Contrast §42's M2-rung build, where the skip was
// conditional on InpUseM2 so M5 needed M1 + M2 + M5.)
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, IDX_M1);
   if(dir == 0) return 0;

   for(int t = IDX_M2; t <= topIdx; t++)
   {
      if(t == IDX_M2 && t < topIdx) continue;   // M2 is not a rung for the tiers above it

      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Daily Bias Filter (H4 tier): D1 is the bias for H4 trades.
// Same alignment semantics as CheckAlign but on D1 — D1 bullish
// (price + chikou above tenkan, kijun and cloud) allows only H4
// buys, D1 bearish only H4 sells. A D1 close INSIDE the cloud
// (or unreadable) returns 0 — no new H4 trades then.
//==============================================================

int DailyAlign(int s)
{
   ENUM_TIMEFRAMES tf = PERIOD_D1;

   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ichD1[s], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;   // D1 close inside the cloud — no H4 trades

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ichD1[s], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Cloud Bias Filter: the cloud must carry the trade's bias
// (Span A above Span B for a long, below for a short) at BOTH
// the last closed bar (the immediate cloud where price sits)
// and the far end of the future-cloud window. This is the
// parent's full check — the strictest form. Used ONLY on the
// M1 timeframe (see LevelCloudBiasOK). Unreadable values count
// as blocking.
//==============================================================

bool CloudBiasOK(int s, int tfIdx, int dir)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1,         1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1,         1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aNow[0] > bNow[0] && aFar[0] > bFar[0];
   return aNow[0] < bNow[0] && aFar[0] < bFar[0];
}

//==============================================================
// Cloud Bias Filter — FUTURE-ONLY: the far end of the future-
// cloud window (Kijun bars ahead of the last closed bar) must
// carry the trade's bias; the immediate cloud where price sits
// may be either direction. Used for every timeframe from M2 up
// in the level gate, and for the H1 stand-in bias confirmation
// (InpH1BiasCloudCheck).
//==============================================================

bool CloudBiasFarOK(int s, int tfIdx, int dir)
{
   double aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aFar[0] > bFar[0];
   return aFar[0] < bFar[0];
}

//==============================================================
// Level Cloud Bias Gate: applies to every tier — the tier's TF
// (lvl+1, always M2 or above) needs only the FUTURE cloud in the
// trade's direction; the TF directly below it in the CHAIN is
// checked as well. The two lowest tiers both sit directly on M1:
//   * M2 (the scalp tier) — its chain is M1 + M2, so M1 is below it.
//   * M5 — M2 is deliberately NOT a rung in this build, so M1 is
//     still the TF below it. This is the case the renumbering would
//     have broken: it used to be the "lvl == 0" branch, and 0 is now
//     M2, which would have given M5 future-only treatment on M2 and
//     left M1 unchecked entirely.
// M1 always carries the FULL check (current AND future cloud). From
// M15 up the TF below is M5 or higher, so future-only applies.
//
// The M2 tier's OWN cloud is a separate switch, InpM2CloudFull:
//   false (default) — M2 takes the M5+ rule (future cloud only), i.e.
//                     the live build's "M1 full / M5+ future-only" split
//                     simply extended one timeframe down. This is what
//                     makes the fork "the live build plus a tier".
//   true            — M2 takes the M1-style FULL check (current AND
//                     future), on the argument that a 2-minute bar is
//                     close in character to M1. This matches the sibling
//                     M2 build (experimental-bottomup-stack-kihon-po3-
//                     veto-m2tier-ea.mq5, InpM2CloudFull = true), so set
//                     it true before comparing the two M2 experiments:
//                     their scalp trade sets are NOT comparable while the
//                     two builds disagree on this rule.
// The switch affects the M2 tier only. M5 and above are untouched.
//==============================================================

bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   // M1 tier: its chain is M1 and nothing else, so there is no "TF below"
   // to confirm — the M1 cloud in full IS the whole gate.
   if(lvl == LVL_M1) return CloudBiasOK(s, IDX_M1, dir);

   if(lvl == LVL_M2)
   {
      bool own = InpM2CloudFull ? CloudBiasOK(s, IDX_M2, dir)      // M1-style full check
                                : CloudBiasFarOK(s, IDX_M2, dir);  // M5+ style, future only
      if(!own) return false;
      return CloudBiasOK(s, IDX_M1, dir);                     // M1 in full, always
   }

   if(!CloudBiasFarOK(s, lvl, dir)) return false;          // tier TF — M5+ — future cloud only
   if(lvl == LVL_M5) return CloudBiasOK(s, IDX_M1, dir);   // M5 sits on M1 — current AND future
   return CloudBiasFarOK(s, lvl - 1, dir);                 // M15+ — TF below, future cloud only
}

//==============================================================
// H4 Bias Filter: H4 is the bias for the whole stack. Every tier
// only trades in H4's direction — H4 bullish means only buys on
// all timeframes (a lower-TF sell is just a pullback), H4 bearish
// means only sells. If H4 has no alignment, no trades open —
// except on the tiers the new H1 stand-in bias covers (below).
//==============================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

//==============================================================
// M30 Bias Filter (NEW) — the scalp tier's OWN bias.
//
// This is NOT the H1-style stand-in of the parent build and NOT
// the last-resort M30 stand-in of the older M30-bias experiment:
// it is the sole directional gate on the M2 tier, consulted
// unconditionally and independently of H4 and H1. The test is the
// identical price+chikou alignment every timeframe M1..D1 uses
// (see CheckAlign), so "M30 bias" means the same thing here as
// "H4 bias" does one tier up.
//
// Consequences, all intended:
//   * The scalp tier trades while H4 is FLAT — it does not need
//     the H1 stand-in's permission, or H4's.
//   * The scalp tier also trades AGAINST an aligned H4. That is
//     counter-trend scalping by design, not an oversight: the M1+M2
//     chain is short-lived and exits on the M2 kumo touch, so it is
//     not held into the H4 trend. If that is ever unwanted, set
//     InpM30ScalpBias = false and gate the tier some other way.
//==============================================================

int M30Bias(int s)
{
   return CheckAlign(s, IDX_M30);   // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

//==============================================================
// H1 Bias Filter (NEW). The stand-in bias for the lower tiers:
// same alignment test as the H4 bias, one timeframe down, with
// an optional H1 cloud-bias confirmation on top. It is only ever
// consulted by EntryBiasOK() below, and only for the tiers the
// user has opened up via InpH1BiasMaxTier.
//==============================================================

bool H1BiasOK(int s, int dir)
{
   int h1 = CheckAlign(s, IDX_H1);
   if(h1 != dir) return false;      // H1 flat or opposed — nothing to stand in with

   // Optional extra confirmation: the H1 kumo's far end (future
   // cloud) must be twisted the trade's way — the same future-only
   // rule that applies to every M2+ timeframe in the level gate.
   // The immediate cloud is NOT required to match.
   if(InpH1BiasCloudCheck && !CloudBiasFarOK(s, IDX_H1, dir)) return false;

   return true;
}

// Is this tier allowed to fall back on the H1 bias at all?
bool H1BiasTier(int lvl)
{
   if(InpH1BiasMode == H1BIAS_OFF)     return false;
   if(lvl >= LEVELS - 1)               return false;   // never the H4 tier
   return lvl <= (int)InpH1BiasMaxTier;
}

//==============================================================
// Does ANY level other than this one hold an open position?
//
// The parent asked a narrower question — "does one of the five LIVE
// tiers hold a position" — because it had a single M30-biased tier
// (M2) and the only hazard was M2 opening against a live trade. With
// M1 tradable there are now TWO tiers taking direction from M30, and
// they can collide with each other as well as with the live tiers, so
// the scan has to cover every other level.
//
// Why either bottom tier needs this, and the live tiers do not: the
// entry scan SKIPS a level that already holds a position instead of
// evaluating it, and the supersede loop only walks BELOW the tier that
// is opening (`l < topTier`). So a tier already running is never closed
// by a new entry and never blocks one. For the five live tiers that is
// the parent's behaviour, left exactly as it is — they all answer to H4,
// so they cannot disagree about direction. M1 and M2 answer to M30
// instead: with an H4 long running, M1 can align SHORT on a later bar
// and open against it. On a netting account MT5 nets the two orders,
// shrinking or closing the live trade behind the EA's back while
// state[] still reports it open.
//
// InpScalpNeedsFlatSymbol = false restores the parent's looser
// semantics for both bottom tiers.
//==============================================================

bool OtherLevelBusy(int s, int lvl)
{
   for(int k = 0; k < LEVELS; k++)
   {
      if(k == lvl) continue;                    // the tier being evaluated is flat by construction
      if(state[s][k] != 0) return true;
   }
   return false;
}

//==============================================================
// Entry Bias Gate: H4 primary, H1 stand-in for the five live
// tiers; M30 for the M2 scalp tier (a separate regime).
//
//   0. M2 SCALP TIER -> returns before any of this. Its gate is
//      InpM30ScalpBias x M30 alignment, or nothing at all when the
//      switch is off. H4 and H1 are never consulted for it, so it
//      may scalp while H4 is flat or even against an aligned H4.
//   1. H4 aligned WITH the trade  -> allowed, whatever the tier.
//      This is the primary path.
//   2. H4 FLAT -> the tiers at or below InpH1BiasMaxTier may still
//      open if H1 carries the trade — an undecided H4 no longer
//      freezes the whole stack.
//   3. H4 aligned AGAINST the trade -> still blocked, unless the
//      user opts into H1BIAS_ALWAYS.
//
// Writes into 'via' the bias that authorised the entry so the caller
// can log it: "H4", "H1" (stand-in on a flat H4), "H1x" (stand-in
// against an aligned H4), "M30" (the scalp tier's own bias), "--"
// when no bias gate applied at all.
//==============================================================

bool EntryBiasOK(int s, int lvl, int dir, string &via)
{
   via = "--";

   //--- M2 SCALP TIER (NEW): a separate bias regime, not a rung on the
   //--- H4/H1 ladder. It returns here and never reaches the code below,
   //--- so H4 and H1 are not consulted for it at all.
   //--- M1 TIER (NEW): same separate regime as the M2 scalp — M30 alone,
   //--- H4 and H1 never consulted. Its own switch so the two scalp tiers
   //--- can be gated independently.
   if(lvl == LVL_M1)
   {
      if(!InpM1M30Bias) return true;           // gate off — bare M1 alignment
      if(M30Bias(s) != dir) return false;      // M30 flat or opposed — no M1 trade
      via = "M30";
      return true;
   }

   if(lvl == LVL_M2)
   {
      if(!InpM30ScalpBias) return true;        // gate off — M1+M2 chain alone
      if(M30Bias(s) != dir) return false;      // M30 flat or opposed — no scalp
      via = "M30";
      return true;
   }

   if(!InpH4Bias)
   {
      // H4 bias switched off: the H1 stand-in, where enabled, is the only
      // directional gate left on those tiers. Higher tiers stay ungated,
      // exactly as they were when the H4 bias is switched off.
      if(!H1BiasTier(lvl)) return true;
      if(!H1BiasOK(s, dir)) return false;
      via = "H1";
      return true;
   }

   int h4 = H4Bias(s);
   if(h4 == dir) { via = "H4"; return true; }          // primary path

   if(!H1BiasTier(lvl)) return false;                  // H1/H4 tiers need H4 itself
   if(h4 != 0 && InpH1BiasMode != H1BIAS_ALWAYS)       // H4 is aligned the other way
      return false;
   if(!H1BiasOK(s, dir)) return false;

   via = (h4 == 0) ? "H1" : "H1x";   // H1x = taken against an aligned H4
   return true;
}

//==============================================================
// Exit Check: price TOUCHES the level TF's cloud edge — no wait
// for a candle to close inside it. A long (entered above the
// cloud) exits when the bid touches the cloud's upper edge; a
// short (entered below) exits when the ask touches the lower
// edge. Evaluated once per closed M1 bar, so a touch triggers
// the exit within a minute. This is the trade's main exit; the
// BE/chandelier stop is the profit-protection layer on top.
//==============================================================

bool InCloudTouch(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   if(dir ==  1)
   {
      double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
      return bid <= MathMax(senA[0], senB[0]);
   }
   if(dir == -1)
   {
      double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
      return ask >= MathMin(senA[0], senB[0]);
   }
   return false;
}

//==============================================================
// Utility Functions
//==============================================================

string PCTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   int h = dt.hour;
   string ampm = (h >= 12) ? "PM" : "AM";
   if(h == 0) h = 12;
   else if(h > 12) h -= 12;
   return IntegerToString(h) + ":" + StringFormat("%02d", dt.min) + " " + ampm;
}

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//==============================================================
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry, in three equity tiers that DE-RISK as the
// account grows: full regime below InpRiskTier2At (M2 0.5%,
// M5/M15 1%, M30 5%, H1 10%, H4 20%), half regime between the
// tiers (0.25/0.5/0.5/2.5/5/10), and the tiny regime at
// InpRiskTier3At and above (0.05/0.1/0.1/0.2/1/2). Sizing measures
// the % against a reference distance of ATR(level TF) x
// InpRiskATRMult, the same ATR-based sizing philosophy as the H4
// VPS build. More equity -> more risk money -> bigger lots at the
// same ATR distance; no multipliers on top. Falls back to
// InpFixedLots when the sizing data is unavailable, and every
// order is capped to the free margin so it fills fully.
//
// NOTE the switch is on LEVEL indices, so the M2 tier's arrival
// shifted all five existing cases up by one. Left unshifted every
// tier would have been sized with the row below it — H4 would have
// risked H1's 10% instead of 20%.
//
// NOTE ALSO: these are SIZING percentages, not the money at risk.
// InpRiskATRMult (2) and InpDisasterATRMult (8) differ, so a
// stop-out costs about FOUR TIMES the figure named here — band 1
// H4's "20%" is ~80% of equity at its disaster stop. That is the
// parent build's design, unchanged by this fork.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // Highest band first — the edges are ascending, so the first match wins
   // and each test needs only its own lower edge.
   int band = 1;
   if(eq >= InpRiskTier5At)      band = 5;
   else if(eq >= InpRiskTier4At) band = 4;
   else if(eq >= InpRiskTier3At) band = 3;
   else if(eq >= InpRiskTier2At) band = 2;

   switch(lvl)
   {
      case LVL_M1:  switch(band){ case 5: return InpRiskPctM1_T5;  case 4: return InpRiskPctM1_T4;
                                  case 3: return InpRiskPctM1_T3;  case 2: return InpRiskPctM1_T2;  } return InpRiskPctM1;
      case LVL_M2:  switch(band){ case 5: return InpRiskPctM2_T5;  case 4: return InpRiskPctM2_T4;
                                  case 3: return InpRiskPctM2_T3;  case 2: return InpRiskPctM2_T2;  } return InpRiskPctM2;
      case LVL_M5:  switch(band){ case 5: return InpRiskPctM5_T5;  case 4: return InpRiskPctM5_T4;
                                  case 3: return InpRiskPctM5_T3;  case 2: return InpRiskPctM5_T2;  } return InpRiskPctM5;
      case LVL_M15: switch(band){ case 5: return InpRiskPctM15_T5; case 4: return InpRiskPctM15_T4;
                                  case 3: return InpRiskPctM15_T3; case 2: return InpRiskPctM15_T2; } return InpRiskPctM15;
      case LVL_M30: switch(band){ case 5: return InpRiskPctM30_T5; case 4: return InpRiskPctM30_T4;
                                  case 3: return InpRiskPctM30_T3; case 2: return InpRiskPctM30_T2; } return InpRiskPctM30;
      case LVL_H1:  switch(band){ case 5: return InpRiskPctH1_T5;  case 4: return InpRiskPctH1_T4;
                                  case 3: return InpRiskPctH1_T3;  case 2: return InpRiskPctH1_T2;  } return InpRiskPctH1;
      case LVL_H4:  switch(band){ case 5: return InpRiskPctH4_T5;  case 4: return InpRiskPctH4_T4;
                                  case 3: return InpRiskPctH4_T3;  case 2: return InpRiskPctH4_T2;  } return InpRiskPctH4;
   }
   return 0.0;
}

double RiskLots(int s, int lvl)
{
   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) return InpFixedLots;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;

   // A hard-SL tier is sized against the stop it will REALLY run, not the
   // 2xATR reference. Without this the risk table would be fiction on those
   // tiers: lots sized for a 2xATR loss but stopped out at a fixed 20 pips
   // risk whatever ratio those two distances happen to have that minute.
   // Sizing off the real stop makes InpRiskPct* mean exactly what it says —
   // and note the consequence: on M1/M2/M5 a stop-out now costs 1x the
   // stated percent, where on M15+ it still costs 4x (2xATR sized, 8xATR
   // stopped). The two halves of the ladder are no longer comparable.
   double stopDist = HardStopDistance(s, lvl, a[0]);
   if(stopDist <= 0.0) stopDist = a[0] * InpRiskATRMult;

   double tickValue = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return InpFixedLots;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLots;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : InpFixedLots;
}

// Scale a single order down so it commits at most InpMarginUsePct % of the
// free margin (R5: the parent committed up to 100%, leaving nothing against
// floating drawdown). lots never drops below the broker minimum.
void CapLotsToMargin(string sym, bool isBuy, double &lots)
{
   if(lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   double budget  = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (InpMarginUsePct / 100.0);
   double maxLots = budget * lots / marginOne;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lotStep > 0) maxLots = MathFloor(maxLots / lotStep) * lotStep;
   maxLots = MathMax(lotMin, maxLots);
   if(lots > maxLots) lots = maxLots;
}

//==============================================================
// Trading Functions
//==============================================================

//==============================================================
// Hard take profit — M2 and M5 only.
//
// A pip is InpPipPoints * SYMBOL_POINT, the same convention the
// fixed-TP sibling (experimental-m1-m2-fixed-tp-ea.mq5) uses: on a
// 2-decimal gold feed one pip is 0.10 of price, so 4000.00 -> 4012.00
// is 120 pips. On a 3-decimal feed set InpPipPoints = 100.
//
// The target is ADDITIVE. It does not replace anything: the kumo-touch
// exit, the rejection candle, the BE stop, the chandelier trail and the
// disaster stop all still run on these two tiers, and whichever comes
// first ends the trade. So this can only shorten an M2/M5 trade that
// would otherwise have run to a managed exit — never extend one.
//
// LevelTPPips returns 0 for every tier above M5, which is how the rest
// of the code knows a level takes no target: 0 is also the "no TP"
// value MT5 itself uses, so no separate flag is needed.
//==============================================================
// Points per pip for a symbol. InpPipPoints > 0 is taken literally;
// 0 means AUTO, which resolves the GOLD convention — one pip is 0.10 of
// price — against whatever digit count the feed actually uses:
//
//   2-decimal gold (point 0.01 ) -> 10  points per pip -> 30 pips = 3.00
//   3-decimal gold (point 0.001) -> 100 points per pip -> 30 pips = 3.00
//
// so the same pip figure means the same PRICE distance on either feed and
// a feed change cannot silently move every target by a factor of ten.
// AUTO is gold-specific by design: on a 5-digit FX symbol it would make a
// pip 0.10 of price, which is 1000 FX pips — set InpPipPoints explicitly
// (10 for 5-digit FX) when trading anything but gold.
double PipPoints(int s)
{
   if(InpPipPoints > 0.0) return InpPipPoints;
   double point = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   if(point <= 0.0) return 0.0;
   return MathRound(0.10 / point);
}

double PipPrice(int s)
{
   return PipPoints(s) * SymbolInfoDouble(syms[s], SYMBOL_POINT);
}

// Hard stop distance for a tier, in pips. 0 means "this tier has no hard
// stop" — M15 and above keep the parent's wide 8xATR disaster stop alone.
double LevelSLPips(int lvl)
{
   if(!InpHardSLEnabled) return 0.0;
   if(lvl == LVL_M1) return InpSLPipsM1;
   if(lvl == LVL_M2) return InpSLPipsM2;
   if(lvl == LVL_M5) return InpSLPipsM5;
   return 0.0;                      // M15, M30, H1, H4 — disaster stop only, as in the parent
}

// The stop distance a hard-SL tier will ACTUALLY run, in price units.
//
// Clamped to the disaster distance so the hard stop can only ever be the
// TIGHTER of the two: on a volatile feed a fixed 20 pips could otherwise
// exceed 8xATR and quietly become a WIDER stop than the parent's, which is
// the opposite of the point. Returns 0 when the tier has no hard stop.
double HardStopDistance(int s, int lvl, double atrVal)
{
   double pips = LevelSLPips(lvl);
   if(pips <= 0.0) return 0.0;

   double dist = pips * PipPrice(s);
   if(InpDisasterStopEnabled && atrVal > 0.0)
      dist = MathMin(dist, atrVal * InpDisasterATRMult);
   return dist;
}

double LevelTPPips(int lvl)
{
   if(!InpHardTPEnabled) return 0.0;
   if(lvl == LVL_M1) return InpTPPipsM1;
   if(lvl == LVL_M2) return InpTPPipsM2;
   if(lvl == LVL_M5) return InpTPPipsM5;
   return 0.0;                      // M15, M30, H1, H4 — unchanged from the parent
}

// The target price for a level, anchored at the ENTRY price so it never
// drifts with the current quote (the same anchoring the disaster stop
// uses). Returns 0 when this level takes no target, when the level has
// no entry reference yet, or when the broker's minimum stop distance
// makes the target invalid — 0 being MT5's "no TP".
double LevelTPPrice(int s, int lvl, int dir, double anchor)
{
   double pips = LevelTPPips(lvl);
   if(pips <= 0.0 || anchor <= 0.0) return 0.0;

   string sym     = syms[s];
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   double tp = NormalizeDouble(dir == 1 ? anchor + pips * PipPrice(s)
                                        : anchor - pips * PipPrice(s), digits);

   // A long's TP fills on the BID, a short's on the ASK — validate against
   // the side that will actually trip it, exactly as the disaster SL does.
   double bidNow = SymbolInfoDouble(sym, SYMBOL_BID);
   double askNow = SymbolInfoDouble(sym, SYMBOL_ASK);
   bool   valid  = (dir == 1) ? (tp > bidNow + minDist)
                              : (tp > 0 && tp < askNow - minDist);
   return valid ? tp : 0.0;
}

// 'via' names the bias that authorised the entry ("H4", "H1" stand-in,
// "H1x" counter-H4 stand-in, "--" none) — logged so the H1-bias trades
// are separable from the H4 ones when reviewing the journal.
bool OpenLevel(int s, int lvl, int dir, double lots, string via)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // R5: pick a filling mode this symbol actually supports — CTrade's FOK
   // default gets retcode 10030 (invalid fill) on IOC-only brokers.
   trade.SetTypeFillingBySymbol(sym);

   // R3: disaster stop — a wide hard SL bounding gap/disconnect loss.
   // Anchored at the entry price so the tail definition is fixed; the BE/
   // chandelier layer takes it over once the trade turns green. If ATR or
   // the broker distance check makes it invalid right now, the order goes
   // out without it and ManageLevelProtection re-attaches next minute.
   double sl = 0.0;
   if(InpDisasterStopEnabled || LevelSLPips(lvl) > 0.0)
   {
      double a[1];
      if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) > 0 && a[0] > 0)
      {
         double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
         double minDist = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
         int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

         // M1/M2/M5 take their tight fixed stop; every tier above keeps the
         // wide 8xATR disaster stop. Either way the broker's minimum stop
         // distance is the floor, so a stop too tight to place is widened to
         // the nearest legal level rather than dropped.
         double want    = HardStopDistance(s, lvl, a[0]);
         if(want <= 0.0) want = a[0] * InpDisasterATRMult;
         double dist    = MathMax(want, minDist + point);
         sl             = NormalizeDouble((dir == 1) ? price - dist : price + dist, digits);

         // A long's SL triggers on the BID, a short's on the ASK — validate
         // against the side that will actually trip it.
         double bidNow  = SymbolInfoDouble(sym, SYMBOL_BID);
         double askNow  = SymbolInfoDouble(sym, SYMBOL_ASK);
         bool   slValid = (dir == 1) ? (sl > 0 && sl < bidNow - minDist)
                                     : (sl > 0 && sl > askNow + minDist);
         if(!slValid) sl = 0.0;
      }
   }

   // Hard TP on the two scalp-side tiers, anchored at the entry price. If
   // the broker distance check makes it invalid right now the order goes
   // out without it and ManageLevelProtection re-attaches next minute,
   // the same self-healing path the disaster stop uses.
   double tp = LevelTPPrice(s, lvl, dir, price);

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, tp, comment)
                        : trade.Sell(lots, sym, price, sl, tp, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string slNote = (LevelSLPips(lvl) > 0.0 && sl > 0.0)
                      ? ", SL " + DoubleToString(LevelSLPips(lvl), 1) + "p @ " +
                        DoubleToString(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS))
                      : "";
      string tpNote = "";
      if(LevelTPPips(lvl) > 0.0)
         tpNote = (tp > 0.0)
                  ? ", TP " + DoubleToString(LevelTPPips(lvl), 1) + "p @ " +
                    DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS))
                  : ", TP deferred (broker distance)";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + slNote + tpNote + ")";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the level for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + tfName[lvl] + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1))) return false;
   }
   return true;
}

//==============================================================
// Profit Protection (VPS-style systems, per level):
//   * Break-even — once the trade is in profit by >= the ATR
//     threshold (InpBEProfitATR x ATR for M2/M5/M15/M30, the tighter
//     InpBEProfitH1H4 x ATR for H1/H4), the stop moves to entry
//     plus InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — H1/H4 levels trail the stop behind the
//     peak once profitable by InpTrailActivateATR x ATR; the
//     lower levels (including the M2 scalp tier) arm it only on a
//     spike (InpSpikeLockATR x ATR). The reference is the highest
//     high / lowest low of the level TF, including the bar still
//     forming; it only ever tightens and never sits inside the
//     broker minimum stop.
// ATR comes from the level's own TF, so H4/H1 protection is sized
// to those timeframes and the scalp tier's to M2's. The only hard
// stop is the wide R3 disaster SL; if it ever goes missing, it is
// re-attached here.
//==============================================================

bool LevelTicket(int s, int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      if(comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1)) return true;
   }
   return false;
}

void ManageLevelProtection(int s, int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   // The reference point is the extreme of the level-TF bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[lvl], 0, 1, tfx) <= 0) return;
   ArraySetAsSeries(tfx, true);

   bool isLong = (dir == 1);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s][lvl]) peakHigh[s][lvl] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s][lvl]) peakLow[s][lvl] = tfx[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!LevelTicket(s, lvl, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   // Every PositionModify below must carry the CURRENT TP back in: the
   // parent passed a bare 0 in that slot, which was correct when no level
   // ever had a target, but would now strip the M2/M5 target the first
   // time BE or the trail fired. tpCur is re-read after each modify that
   // succeeds, so the value handed on is never stale.
   double tpCur = PositionGetDouble(POSITION_TP);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Self-heal a missing target the same way the disaster stop self-heals:
   // it was skipped at send time because the broker distance check failed
   // then, or it was stripped later. Anchored at the ENTRY price, which
   // SyncStateFromPositions restores from POSITION_PRICE_OPEN after a
   // restart, so the target lands where it would have at open.
   if(tpCur == 0.0 && LevelTPPips(lvl) > 0.0)
   {
      double tpHeal = LevelTPPrice(s, lvl, dir, entryPrice[s][lvl]);
      if(tpHeal > 0.0)
      {
         if(trade.PositionModify(ticket, slCur, tpHeal))
            tpCur = tpHeal;
         else
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl] + " TP attach failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   // R3: self-heal a missing disaster stop (it was skipped at send time
   // because it was invalid then, or stripped later). Anchored at the ENTRY
   // price so the tail definition never drifts; only attaches while no
   // other stop exists — BE/chandelier take over from there and only ever
   // tighten.
   if((InpDisasterStopEnabled || LevelSLPips(lvl) > 0.0) && slCur == 0.0)
   {
      // Re-attach the stop this tier is supposed to run — the tight hard one
      // where it has it, the wide disaster one otherwise. Anchored at the
      // ENTRY price, so a tier that lost its stop does not silently get a
      // wider one measured from wherever price has drifted to.
      double healDist = HardStopDistance(s, lvl, atrVal);
      if(healDist <= 0.0) healDist = InpDisasterATRMult * atrVal;
      double dSl = NormalizeDouble(isLong ? entryPrice[s][lvl] - healDist
                                          : entryPrice[s][lvl] + healDist,
                                   digits);
      bool okD = isLong ? (dSl > 0 && dSl < bid - minDist)
                        : (dSl > ask + minDist);
      if(okD)
      {
         if(trade.PositionModify(ticket, dSl, tpCur))
            slCur = dSl;
         else
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl] + " disaster SL attach failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   // Break-even: tighter arming threshold on the long-running H1/H4 levels
   // (LVL_H1, not the bare 3 it used to be — 3 is now M30, and the bare
   // number would have handed M30 the H1/H4 rule and taken it from H1)
   double beATR = (lvl >= LVL_H1) ? InpBEProfitH1H4 : InpBEProfitATR;
   if(!beMoved[s][lvl])
   {
      bool armed = isLong ? (bid >= entryPrice[s][lvl] + beATR * atrVal)
                          : (ask <= entryPrice[s][lvl] - beATR * atrVal);
      if(armed)
      {
         double slNew = isLong ? entryPrice[s][lvl] + InpBECoverPoints * point
                               : entryPrice[s][lvl] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist)
                          : (slNew < slCur - point && slNew > ask + minDist);
         if(ok)
         {
            if(!trade.PositionModify(ticket, slNew, tpCur))
               Print(PCTime() + " | " + syms[s] + " " + tfName[lvl] + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // Chandelier trail behind the peak. H1/H4 levels get the full
   // chandelier: it arms once the trade is profitable by InpTrailActivateATR
   // x ATR so long-running higher-TF trades are always protected. The lower
   // levels keep the spike-gated trail (InpSpikeLockATR x ATR). Only ever
   // tightens, keeps out of the broker minimum stop distance, and skips
   // microscopic improvements (0.3x ATR).
   // Re-read the current stop first — the BE block above may have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);
   tpCur = PositionGetDouble(POSITION_TP);

   double armATR = (lvl >= LVL_H1) ? InpTrailActivateATR : InpSpikeLockATR;
   bool armed = isLong ? (bid >= entryPrice[s][lvl] + armATR * atrVal)
                       : (ask <= entryPrice[s][lvl] - armATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s][lvl] - InpTrailATR * atrVal
                            : peakLow[s][lvl] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist &&
                          slNew - slCur >= 0.3 * atrVal)
                       : (slNew < slCur - point && slNew > ask + minDist &&
                          slCur - slNew >= 0.3 * atrVal);
      if(ok)
      {
         if(!trade.PositionModify(ticket, slNew, tpCur))
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl] + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Rejection Candle Exit: closes a trade when a VERY STRONG
// rejection forms against it on the tier TF (last closed bar).
// All four conditions must hold — a swing sweep plus a dominant
// wick plus a strong close-back on a candle whose body opposes
// the trade:
//   Bearish rejection (kills a LONG):
//     - bearish body (c1 < o1)
//     - takes out the swing high of the previous
//       InpRejSwingBars bars (h1 > highest high before it)
//     - upper wick >= InpRejWickPct of the candle's total range
//     - close in the bottom InpRejClosePct of the range
//       (closed strongly back from the sweep high)
//   Bullish rejection (kills a SHORT): mirrored.
// Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandle(int s, int tfIdx)
{
   int need = 2 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   double o1 = r[1].open, c1 = r[1].close, h1 = r[1].high, l1 = r[1].low;

   // Swing extreme of the InpRejSwingBars bars before the rejection candle
   double swingHi = r[2].high, swingLo = r[2].low;
   for(int i = 3; i < need; i++)
   {
      if(r[i].high > swingHi) swingHi = r[i].high;
      if(r[i].low  < swingLo) swingLo = r[i].low;
   }

   double range = h1 - l1;
   if(range <= 0) return 0;

   // Bearish rejection: sweeps the swing high and closes strongly back
   if(c1 < o1 && h1 > swingHi)
   {
      double upperWick = h1 - o1;               // bearish: high minus open
      double closeBack = c1 - l1;               // distance closed back from the low
      if(upperWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return -1;
   }

   // Bullish rejection: sweeps the swing low and closes strongly back
   if(c1 > o1 && l1 < swingLo)
   {
      double lowerWick = o1 - l1;               // bullish: open minus low
      double closeBack = h1 - c1;               // distance closed back from the high
      if(lowerWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return 1;
   }
   return 0;
}

// Close a level's positions with a notification; returns true only
// when nothing remains open, so a failed close is retried next bar.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[l] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + tfName[l] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[l] + " exit signal but positions still open — will retry");
   return false;
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // VPS perf: all logic runs only on closed M1 bars, which change at most
   // once per minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Scalp-tier readiness read-out, deferred out of OnInit on purpose:
      // at init the M2 series of a non-chart symbol has often not been built
      // yet, and a timeseries accessor returns 0 while it is under
      // construction — so deciding there can report "no M2 history" for a
      // perfectly healthy feed and never correct itself. Fire once, on the
      // first closed M1 bar where M2 actually carries enough bars to be read.
      if(scalpReady[s] && !scalpReported[s] && Bars(syms[s], PERIOD_M2) > Kijun + 1)
      {
         scalpReported[s] = true;
         Print(PCTime() + " | " + syms[s] + " M2 scalp tier ACTIVE (M1+M2 chain, bias " +
               (InpM30ScalpBias ? "M30" : "none — chain alone") + ", M2 cloud " +
               (InpM2CloudFull ? "FULL current+future" : "future-only") + ").");
      }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge
         if(state[s][l] != 0 && InCloudTouch(s, l, state[s][l]))
            ExitLevel(s, l, "kumo touch");

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, l);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entry consolidation: when several tiers align at once, only the
      // LARGEST one opens (highest TF wins). Any smaller tier already
      // running on the symbol is closed first — e.g. M15 and M30 align
      // together: the running M15 trade closes and only M30 opens.
      int    topTier = -1;
      int    topDir  = 0;
      string topVia  = "--";
      // R2: never add exposure while an unmanageable (unparseable-comment)
      // magic position sits on this symbol; exits/protection still run.
      if(!symBlockedUnknown[s] && SpreadOK(syms[s]))
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;
            // Scalp-tier gates. Both bottom tiers take their direction from
            // M30 rather than H4, so either could open AGAINST a running
            // higher-tier trade and net against it — hence the flat-symbol
            // rule, now covering every other level rather than only the five
            // live ones (a running M1 must block M2, and the reverse).
            if(l == LVL_M1)
            {
               if(!InpM1Tier) continue;
               if(InpScalpNeedsFlatSymbol && OtherLevelBusy(s, l)) continue;
            }
            if(l == LVL_M2)
            {
               if(!InpM2ScalpTier || !scalpReady[s]) continue;
               if(InpScalpNeedsFlatSymbol && OtherLevelBusy(s, l)) continue;
            }
            int st = ChainAligned(s, l);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Directional bias: H4 as before, with the H1 stand-in for the
            // live tiers when H4 has no direction of its own. The M2 scalp
            // tier is a separate regime — M30, or nothing (see EntryBiasOK).
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            topTier = l;
            topDir  = st;
            topVia  = via;
            break;
         }
      }

      if(topTier >= 0)
      {
         // Close any smaller (lower-tier) trades still running
         for(int l = 0; l < topTier; l++)
         {
            if(state[s][l] != 0)
            {
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l] +
                            " (superseded by " + tfName[topTier] + ")";
               Print(msg); SendNotification(msg);

               if(CloseLevelPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l] + " superseded but positions still open — will retry");
            }
         }

         // Open only the largest tier
         double lots = RiskLots(s, topTier);
         CapLotsToMargin(syms[s], (topDir == 1), lots);

         if(!OpenLevel(s, topTier, topDir, lots, topVia))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
