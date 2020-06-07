{-# LANGUAGE FlexibleContexts #-}

module Network.AMQP.Streamly
    ( SendInstructions(..)
    , produce
    , consume
    ) where

import Control.Concurrent.MVar
import Control.Monad.IO.Class(MonadIO, liftIO)

import Data.Text(Text)
import Network.AMQP
import Streamly
import qualified Streamly.Internal.Prelude as S
import qualified Streamly.Prelude as S

data SendInstructions = SendInstructions { exchange :: Text, routingKey :: Text, mandatory :: Bool, message :: Message } deriving (Show)
type Queue = Text

-- | Publish the produced messages.
produce :: (IsStream t, MonadAsync m) => Channel -> t m SendInstructions -> t m ()
produce channel = S.mapM send
  where send i = liftIO $ do
                  publishMsg' channel (exchange i) (routingKey i) (mandatory i) (message i)
                  return ()

-- | Stream messages from a queue.
consume :: (IsStream t, MonadAsync m) => Channel -> Queue -> Ack -> t m (Message, Envelope)
consume channel queue ack = S.concatM $ liftIO $ do
  mvar <- newEmptyMVar
  consumeMsgs channel queue NoAck $ putMVar mvar
  return $ S.repeatM $ taking mvar
  where taking :: MonadIO m => MVar (Message, Envelope) -> m (Message, Envelope)
        taking mvar = liftIO $ if ack == Ack
                                 then do
                                        retrieved <- takeMVar mvar
                                        ackEnv $ snd retrieved
                                        return retrieved
                                 else takeMVar mvar
