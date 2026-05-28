# Lumina Performance Notes (Aggressive Optimization Applied)

## Current State
- ModernHomeView now uses LazyVStack + UltraLightGlassCard + .drawingGroup()
- ContentView limited to 6 core tabs during development (prevents loading 20+ complex views at once)
- Using regularMaterial instead of ultraThinMaterial where possible (cheaper)

## Key Fixes Applied
1. Switched to LazyVStack in all long scroll content
2. Created UltraLightGlassCard (fewer layers)
3. Added .drawingGroup() on the entire home content
4. Reduced number of simultaneous tabs during development
5. Reduced ring sizes and spacing

## Still Laggy? Do This:

### 1. Test on Real Device (Most Important)
The simulator is extremely slow with materials + gradients. Real iPhone 14/15/16 will feel 5-10x smoother.

### 2. Profile It
- Run on device
- Open Instruments → SwiftUI Instruments or Time Profiler
- Look for heavy view body evaluations or offscreen rendering

### 3. Further Reductions You Can Do
- Remove some rings from home screen
- Make the 3 progress rings smaller or use one big one
- Turn off some animations temporarily

## Long-term Recommendations
- Use `.drawingGroup()` only on the heaviest screens
- Consider a "High Performance Mode" toggle that disables most materials
- Profile regularly as you add more features

Last optimized: May 2026
