module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.HealthSpec qualified as HealthSpec
import Cardano.StakeCSMT.Application.RunSpec qualified as RunSpec
import Cardano.StakeCSMT.CSMT.BuilderSpec qualified as CSMTBuilderSpec
import Cardano.StakeCSMT.CSMT.CodecsSpec qualified as CSMTCodecsSpec
import Cardano.StakeCSMT.CSMT.RocksDBSpec qualified as CSMTRocksDBSpec
import Cardano.StakeCSMT.HTTP.APISpec qualified as APISpec
import Cardano.StakeCSMT.HTTP.Base16Spec qualified as Base16Spec
import Cardano.StakeCSMT.HTTP.QuerySpec qualified as QuerySpec
import Cardano.StakeCSMT.HTTP.ServerSpec qualified as ServerSpec
import Cardano.StakeCSMT.HTTP.SwaggerSpec qualified as SwaggerSpec
import Cardano.StakeCSMT.History.BuilderSpec qualified as HistoryBuilderSpec
import Cardano.StakeCSMT.History.CodecsSpec qualified as HistoryCodecsSpec
import Cardano.StakeCSMT.History.RocksDBSpec qualified as HistoryRocksDBSpec
import Cardano.StakeCSMT.Ledger.CheckpointSpec qualified as LedgerCheckpointSpec
import Cardano.StakeCSMT.Ledger.ConfigSpec qualified as LedgerConfigSpec
import Cardano.StakeCSMT.Ledger.ReplaySpec qualified as LedgerReplaySpec
import Cardano.StakeCSMT.Ledger.StakeSnapshotSpec qualified as StakeSnapshotSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    HealthSpec.spec
    RunSpec.spec
    CSMTBuilderSpec.spec
    CSMTCodecsSpec.spec
    CSMTRocksDBSpec.spec
    APISpec.spec
    Base16Spec.spec
    QuerySpec.spec
    HistoryBuilderSpec.spec
    HistoryCodecsSpec.spec
    HistoryRocksDBSpec.spec
    ServerSpec.spec
    SwaggerSpec.spec
    LedgerCheckpointSpec.spec
    LedgerConfigSpec.spec
    LedgerReplaySpec.spec
    StakeSnapshotSpec.spec
