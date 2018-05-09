{-# LANGUAGE DeriveFunctor, GeneralizedNewtypeDeriving #-}

-- | A bit like 'Fence', but not thread safe and optimised for avoiding taking the fence
module General.Wait(
    Locked, runLocked,
    Wait(..), runWait, quickly, fromLater, firstJustWaitOrdered, firstJustWaitUnordered
    ) where

import Control.Monad.Extra
import Control.Monad.IO.Class
import Control.Concurrent.Extra
import Data.IORef.Extra


runWait :: Monad m => Wait m a -> m (Wait m a)
runWait (Lift x) = runWait =<< x
runWait x = return x

fromLater :: Monad m => Wait m a -> (a -> m ()) -> m ()
fromLater (Lift x) f = do x <- x; fromLater x f
fromLater (Now x) f = f x
fromLater (Later x) f = x f

newtype Locked a = Locked (IO a)
    deriving (Functor, Applicative, Monad, MonadIO)

runLocked :: Var a -> (a -> Locked b) -> IO b
runLocked var act = withVar var $ \v -> case act v of Locked x -> x

quickly :: Functor m => m a -> Wait m a
quickly = Lift . fmap Now

data Wait m a = Now a
              | Lift (m (Wait m a))
              | Later ((a -> m ()) -> m ())
                deriving Functor

instance Monad m => Applicative (Wait m) where
    pure = Now
    Now x <*> y = x <$> y
    Lift x <*> y = Lift $ (<*> y) <$> x
    Later x <*> Now y = Later $ \c -> x $ \x -> c $ x y
    Later x <*> Lift y = Lift $ do y <- y; return $ Later x <*> y
    Later x <*> Later y = Later $ \c -> x $ \x -> y $ \y -> c $ x y

instance Monad m => Monad (Wait m) where
    return = pure
    (>>) = (*>)
    Now x >>= f = f x
    Lift x >>= f = Lift $ do x <- x; return $ x >>= f
    Later x >>= f = Later $ \c -> x $ \x -> do
        x <- runWait $ f x
        case x of
            Now x -> c x
            Later x -> x c

instance MonadIO m => MonadIO (Wait m) where
    liftIO = Lift . liftIO . fmap Now

firstJustWaitOrdered :: Monad m => (a -> Wait m (Maybe b)) -> [a] -> Wait m (Maybe b)
firstJustWaitOrdered = firstJustM

firstJustWaitUnordered :: MonadIO m => (a -> Wait m (Maybe b)) -> [a] -> Wait m (Maybe b)
firstJustWaitUnordered f = go [] . map f
    where
        -- keep a list of those things we might visit later, and ask for each we see in turn
        go :: MonadIO m => [(Maybe a -> m ()) -> m ()] -> [Wait m (Maybe a)] -> Wait m (Maybe a)
        go later (x:xs) = case x of
            Now (Just a) -> Now $ Just a
            Now Nothing -> Now Nothing
            Later l -> go (l:later) xs
            Lift x -> Lift $ do
                x <- x
                return $ go later (x:xs)
        go [] [] = Now Nothing
        go [l] [] = Later l
        go ls [] = Later $ \callback -> do
            ref <- liftIO $ newIORef $ length ls
            forM_ ls $ \l -> l $ \r -> do
                old <- liftIO $ readIORef ref
                when (old > 0) $ case r of
                    Just a -> do
                        liftIO $ writeIORef' ref 0
                        callback $ Just a
                    Nothing -> do
                        liftIO $ writeIORef' ref $ old-1
                        when (old == 1) $ callback Nothing
