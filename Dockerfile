# Use an official Python runtime as a base image
FROM python:3.12-bullseye

# Ensure Python output is not buffered
ENV PYTHONUNBUFFERED=1

# Set the working directory in the container
WORKDIR /app

# Copy only dependency files first (leverage Docker layer caching)
COPY pyproject.toml poetry.lock ./

# Disable Poetry virtual environments
ENV POETRY_VIRTUALENVS_CREATE=false

# Install Poetry
RUN pip install --no-cache-dir poetry

# Install dependencies
RUN poetry install --no-root --no-dev

# Copy the current directory contents into the container
COPY . .

# Specify the command to run your application
ENTRYPOINT ["python", "src/main.py"]

# If i want poetry to run in venv when i have multiple apps in a container
# ENTRYPOINT ["/root/.cache/pypoetry/virtualenvs/<env-name>/bin/python", "src/main.py"]
