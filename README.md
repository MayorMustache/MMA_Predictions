# MMA_Predictions
Using statistical models and machine learning to predict mma fights

## Structure
- `data/RawData` - directory containing the web scrapped data
- `data/RawData/event_details.csv` - details regarding UFC events
- `data/RawData/fight_details.csv` - details regarding UFC fights
- `data/RawData/fighter_details.csv` - details regarding UFC fighter_details
- `data/RawData/UFC.csv` - merge data of event_details, fight_details and fighter_details
- `data/RawData/scraped_events.csv` - information which events have been scraped
- `data/RawData/upcoming_events.csv` - information regarding upcoming UFC events
- `DataPreparation.r` - creates additionional variabeles with feature engineering
- `MerlesMegaTests.r` - some funny tests on the data based on survival analysis
- `ModelTrainingWinner.r` - creates, finetunes and tests models with the winner being the target variable
- `WebScrapper.py` - Python script for scraping past and upcoming data regarding UFC events and fighters

## License
MIT
