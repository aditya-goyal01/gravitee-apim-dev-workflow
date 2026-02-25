# Contributing to gravitee-dev-workflow

Thank you for your interest in contributing to the gravitee-dev-workflow plugin! Here are the guidelines to help you get started.

## Table of Contents
- [Setup Instructions](#setup-instructions)
- [Skill Development](#skill-development)
- [Hook Creation](#hook-creation)
- [Testing Procedures](#testing-procedures)

## Setup Instructions
1. **Clone the Repository**: 
   ```bash
   git clone https://github.com/aditya-goyal01/gravitee-apim-dev-workflow.git
   cd gravitee-apim-dev-workflow
   ```

2. **Install Dependencies**: 
   Make sure you have Node.js and npm installed. Then run:
   ```bash
   npm install
   ```

3. **Configuration**: 
   Create a `.env` file in the root of the project and configure your environment variables according to your local setup.

4. **Run the Project**: 
   You can start the project using:
   ```bash
   npm start
   ```

## Skill Development
- Familiarize yourself with JavaScript and Node.js, as the plugin is built on these technologies.
- Review the project's codebase and documentation to understand its structure and functionalities.
- Engage in online courses or tutorials related to JavaScript and plugin development.

## Hook Creation
- Hooks are critical for extending the functionality of the gravitee-dev-workflow plugin.
- To create a new hook, follow these steps:
  1. Identify the required functionality.
  2. Create a new file in the `hooks` directory.
  3. Follow the coding standards and conventions used in the project.
  4. Document your hook appropriately.

## Testing Procedures
- It is crucial to test your contributions. Follow these guidelines:
  1. Write unit tests for your code using the provided testing framework.
  2. Run the tests before submitting your changes to ensure everything works as expected:
     ```bash
     npm test
     ```
  3. Ensure that your code coverage meets the project's standards.

## Submitting Changes
- Once you have made your changes, commit them with a clear message:
  ```bash
  git commit -m "Descriptive message about your changes"
  ```
- Push your changes to a new branch and open a pull request.

Thank you for contributing to the gravitee-dev-workflow plugin! We appreciate your efforts to enhance this project.