module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.HealthSpec qualified as HealthSpec
import Cardano.StakeCSMT.CSMT.BuilderSpec qualified as CSMTBuilderSpec
import Cardano.StakeCSMT.CSMT.CodecsSpec qualified as CSMTCodecsSpec
import Cardano.StakeCSMT.CSMT.RocksDBSpec qualified as CSMTRocksDBSpec
import Cardano.StakeCSMT.HTTP.ServerSpec qualified as ServerSpec
import Cardano.StakeCSMT.History.BuilderSpec qualified as HistoryBuilderSpec
import Cardano.StakeCSMT.History.CodecsSpec qualified as HistoryCodecsSpec
import Cardano.StakeCSMT.History.RocksDBSpec qualified as HistoryRocksDBSpec
import Cardano.StakeCSMT.Ledger.ConfigSpec qualified as LedgerConfigSpec
import Cardano.StakeCSMT.Ledger.ReplaySpec qualified as LedgerReplaySpec
import Cardano.StakeCSMT.Ledger.StakeSnapshotSpec qualified as StakeSnapshotSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    HealthSpec.spec
    CSMTBuilderSpec.spec
    CSMTCodecsSpec.spec
    CSMTRocksDBSpec.spec
    HistoryBuilderSpec.spec
    HistoryCodecsSpec.spec
    HistoryRocksDBSpec.spec
    ServerSpec.spec
    LedgerConfigSpec.spec
    LedgerReplaySpec.spec
    StakeSnapshotSpec.spec
