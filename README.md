# Bachelorarbeit_Report
THAB Bachelorthesis Report MatrixExtension

## Building on Microsoft Windows (without MSYS2)

Install Latex from https://www.latex-project.org/get/.
From the options MiKTeX or TeX Live, choose TeX Live.

> When installing from the internet, we recommend downloading and running install-tl-windows.exe.

Download and install install-tl-windows.exe from https://www.tug.org/texlive/windows.html. You may need to open the properties on the .exe file and check the "unblock" checkbox in order to execute the installer.
The installer will install Tex Live to C:\textlive\2025.

```
cd C:\Users\lapto\Documents\Aschaffenburg\BachelorArbeit\Bachelorarbeit_Report
```

## Building on Microsoft Windows with MSYS2

If you want to build using the provided Makefile. You need GNU Make. The easiest way to get GNU Make on Microsoft Windows is to install MSYS2 and install all the maketools. After that open a MSYS2 console and type in:

```
cd /c/Users/lapto/Documents/Aschaffenburg/BachelorArbeit/Bachelorarbeit_Report
make
```

# Equations

```
\begin{equation}
    E=m c^2
\end{equation}
```

# Matrix

https://tex.stackexchange.com/questions/204621/matrix-in-latex

```
\[
\begin{bmatrix}
    a_{11} & a_{12} & a_{13} & \dots  & a_{1n} \\
    a_{21} & a_{22} & a_{23} & \dots  & a_{2n} \\
    \vdots & \vdots & \vdots & \ddots & \vdots \\
    a_{d1} & a_{d2} & a_{d3} & \dots  & a_{dn}
\end{bmatrix}
\]
```

# Code Listing

Into packages.tex import the package listings

```
\usepackage{listings}
```

Then in a Latex file, insert a listing. (DO NOT INSERT GERMAN UMLAUTS!)

```
\begin{lstlisting}
function matmult(A,B,l,m,n)

// Ergebnismatrix C mit Nullen initialisieren
C = zeroes(l,n)

for i = 1 to l  // Schleife ueber die Zeilen von C
  for k = 1 to n  // Schleife ueber die Spalten von C
    for j = 1 to m  // Schleife ueber die Spalten von A / Zeilen von B
      C(i,k) = C(i,k) + A(i,j) * B(j,k)
    end
  end
end

return C
\end{lstlisting}
```

# Glossaries

https://ftp.rrzn.uni-hannover.de/pub/mirror/tex-archive/macros/latex/contrib/glossaries/glossariesbegin.pdf


bthesis_wbischoff_2228538.tex contains the command that outputs the glossary:

```
\printunsrtglossaries % list all entries
```

setup\packages.tex contains the import for the glossary package:

```
\usepackage[sort=none,nogroupskip]{glossaries-extra}
```

setup\packages.tex contains the individual entries for the glossary:

```
\newglossaryentry{RVV}{name={RVV}, description={RISC-V Vector Extensions}}
\newglossaryentry{SISD}{name={SISD}, description={Single Instruction Single Data}}
\newglossaryentry{SIMD}{name={SIMD}, description={Single Instruction Multiple Data}}
\newglossaryentry{XLEN}{name={XLEN}, description={Standardregisterlänge in Bits}}
\newglossaryentry{VLEN}{name={VLEN}, description={Vector-Registerlänge in Bits}}
\newglossaryentry{MLEN}{name={MLEN}, description={Matrix-Registerlänge in Bits}}
```





bthesis_wbischoff_2228538.tex

```
/c/texlive/2025/bin/windows/latexmk -pdf -outdir=out -M -MP -MF bthesis_wbischoff_2228538.d bthesis_wbischoff_2228538
```