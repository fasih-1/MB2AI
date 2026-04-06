# Selector Notes

ManageBac UI can change across schools and over time.

The scraper uses fallback selectors for:
- tasks list container
- task row cards
- title
- class name
- description/instructions
- due date

If scraping breaks, inspect live HTML and update selector groups in src/selectors.py.
