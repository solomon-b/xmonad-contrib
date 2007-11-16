{-# LANGUAGE CPP #-}

----------------------------------------------------------------------------
-- |
-- Module      :  XMonad.Util.Font
-- Copyright   :  (c) 2007 Andrea Rossato
-- License     :  BSD-style (see xmonad/LICENSE)
--
-- Maintainer  :  andrea.rossato@unibz.it
-- Stability   :  unstable
-- Portability :  unportable
--
-- A module for abstracting a font facility over Core fonts and Xft
--
-----------------------------------------------------------------------------

module XMonad.Util.Font  (
                             -- * Usage:
                             -- $usage
                             XMonadFont(..)
                             , initXMF
                             , releaseXMF
                             , initCoreFont
                             , releaseCoreFont
                             , Align (..)
                             , stringPosition
                             , textWidthXMF
                             , textExtentsXMF
                             , printStringXMF
                             , stringToPixel
                            ) where


import Graphics.X11.Xlib
import Control.Monad.Reader
import XMonad
import Foreign
import XMonad.Operations

#ifdef XFT
import Data.List
import Graphics.X11.Xft
import Graphics.X11.Xrender
#endif

-- Hide the Core Font/Xft switching here
data XMonadFont = Core FontStruct
#ifdef XFT
                | Xft  XftFont
#endif

-- $usage
-- See Tabbed or Prompt for usage examples

-- | Get the Pixel value for a named color: if an invalid name is
-- given the black pixel will be returned.
stringToPixel :: String -> X Pixel
stringToPixel s = do
  d <- asks display
  io $ catch (getIt d) (fallBack d)
    where getIt    d = initColor d s
          fallBack d = const $ return $ blackPixel d (defaultScreen d)


-- | Given a fontname returns the font structure. If the font name is
--  not valid the default font will be loaded and returned.
initCoreFont :: String -> X FontStruct
initCoreFont s = do
  d <- asks display
  io $ catch (getIt d) (fallBack d)
      where getIt    d = loadQueryFont d s
            fallBack d = const $ loadQueryFont d "-misc-fixed-*-*-*-*-10-*-*-*-*-*-*-*"

releaseCoreFont :: FontStruct -> X ()
releaseCoreFont fs = do
  d <- asks display
  io $ freeFont d fs

-- | When initXMF gets a font name that starts with 'xft:' it switchs to the Xft backend
-- Example: 'xft: Sans-10'
initXMF :: String -> X XMonadFont
initXMF s =
#ifdef XFT
  if xftPrefix `isPrefixOf` s then
     do
       dpy <- asks display
       xftdraw <- io $ xftFontOpen dpy (defaultScreenOfDisplay dpy) (drop (length xftPrefix) s)
       return (Xft xftdraw)
  else
#endif
      (initCoreFont s >>= (return . Core))
#ifdef XFT
  where xftPrefix = "xft:"
#endif

releaseXMF :: XMonadFont -> X ()
releaseXMF (Core fs) = releaseCoreFont fs
#ifdef XFT
releaseXMF (Xft xftfont) = do
  dpy <- asks display
  io $ xftFontClose dpy xftfont
#endif

textWidthXMF :: Display -> XMonadFont -> String -> IO Int
textWidthXMF _   (Core fs) s = return $ fi $ textWidth fs s
#ifdef XFT
textWidthXMF dpy (Xft xftdraw) s = do
    gi <- xftTextExtents dpy xftdraw s
    return $ xglyphinfo_width gi
#endif

textExtentsXMF :: Display -> XMonadFont -> String -> IO (FontDirection,Int32,Int32,CharStruct)
textExtentsXMF _ (Core fs) s = return $ textExtents fs s
#ifdef XFT
textExtentsXMF _ (Xft xftfont) _ = do
    ascent <- xftfont_ascent xftfont
    descent <- xftfont_descent xftfont
    return (error "Font direction touched", fi ascent, fi descent, error "Font overall size touched")
#endif

-- | String position
data Align = AlignCenter | AlignRight | AlignLeft

-- | Return the string x and y 'Position' in a 'Rectangle', given a
-- 'FontStruct' and the 'Align'ment
stringPosition :: XMonadFont -> Rectangle -> Align -> String -> X (Position,Position)
stringPosition fs (Rectangle _ _ w h) al s = do
  dpy <- asks display
  width <- io $ textWidthXMF dpy fs s
  (_,a,d,_) <- io $ textExtentsXMF dpy fs s
  let y         = fi $ ((h - fi (a + d)) `div` 2) + fi a;
      x         = case al of
                     AlignCenter -> fi (w `div` 2) - fi (width `div` 2)
                     AlignLeft   -> 1
                     AlignRight  -> fi (w - (fi width + 1));
  return (x,y)


printStringXMF :: Display -> Drawable -> XMonadFont -> GC -> String -> String
            -> Position -> Position -> String  -> X ()
printStringXMF d p (Core fs) gc fc bc x y s = do
         io $ setFont d gc $ fontFromFontStruct fs
         [fc',bc'] <- mapM stringToPixel [fc,bc]
         io $ setForeground   d gc fc'
         io $ setBackground   d gc bc'
         io $ drawImageString d p gc x y s

#ifdef XFT
printStringXMF dpy drw (Xft font) _ fc _ x y s = do
  let screen = defaultScreenOfDisplay dpy;
      colormap = defaultColormapOfScreen screen;
      visual = defaultVisualOfScreen screen;
  io $ withXftDraw dpy drw visual colormap $
         \draw -> withXftColorName dpy visual colormap fc $
                   \color -> xftDrawString draw color font x y s
#endif


-- | Short-hand for 'fromIntegral'
fi :: (Integral a, Num b) => a -> b
fi = fromIntegral