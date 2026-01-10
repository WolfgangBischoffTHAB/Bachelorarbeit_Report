LATEX_HOME = /c/texlive/2025/bin/windows
LATEXMK = $(LATEX_HOME)/latexmk
PDFLATEX = $(LATEX_HOME)/pdflatex
DOCNAME = bthesis_wbischoff_2228538

all: out/$(DOCNAME).pdf

out/%.pdf: %.tex
	$(LATEXMK) -pdf -outdir=out -M -MP -MF $*.d $*

Readme.pdf: Readme.tex
	$(PDFLATEX) $<

Readme.tex: Readme.md
	lowdown -Mtitle="Readme - LaTeX Vorlage" -sTlatex --latex-no-numbered $< -o $@
	sed -e '/hyperref/a\\\\usepackage{pmboxdraw}' -i $@

.PHONY: latexvorlage.zip
latexvorlage.zip:
	bsdtar -a -s ",^\.,latexvorlage," --exclude $@ --exclude out/ --exclude-vcs -cf $@ .

.PHONY: clean
clean:
	rm -rf out
	rm *.d

-include *.d
