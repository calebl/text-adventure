# README

Text Adventure is a text-based adventure game using AI to generate the story and the characters.

Neo4j is used to store the graph of the story.
Raix is used to interact with the OpenRouter API.

## Todo

### V0
- [x] Add a basic UI (do everything in the console for now)
- [x] Create a narrator class with Raix
- [ ] Add a way to store user progress (basic save of current transcript)
- [ ] Add a way to load user progress


### VNext
- [ ] Create tests for the narrator class to ensure the prompt is correct
- [ ] create a setup script that will install the dependencies and create a shortcut to the app
- [ ] Add a way to store user inventory
- [ ] experiment with using a local LLM instead of OpenRouter (update Raix)