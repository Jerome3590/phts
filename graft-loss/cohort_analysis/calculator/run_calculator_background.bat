@echo off
cd /d "%~dp0"
start "Calculator Models" /MIN Rscript calculator_models.R > calculator_run.log 2>&1
echo Calculator models started in background. Check calculator_run.log for progress.
