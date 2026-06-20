module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.HealthSpec qualified as HealthSpec
import Cardano.StakeCSMT.HTTP.ServerSpec qualified as ServerSpec
import Cardano.StakeCSMT.Ledger.ConfigSpec qualified as LedgerConfigSpec
import Cardano.StakeCSMT.Ledger.ReplaySpec qualified as LedgerReplaySpec
import Cardano.StakeCSMT.Ledger.StakeSnapshotSpec qualified as StakeSnapshotSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    HealthSpec.spec
    ServerSpec.spec
    LedgerConfigSpec.spec
    LedgerReplaySpec.spec
    StakeSnapshotSpec.spec
