import logging
import sys
from rich.console import Console

from gitlab_pilot import (
    ConnectionManager,
    ProjectManager,
    ProjectResourceManager,
    StageFunctionRegistry,
    VariablesManager,
    PipelineController
)

# Set up logging configuration to log INFO and higher levels to both console and a file
logging.basicConfig(
    level=logging.ERROR,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),                       # Log to console
        logging.FileHandler('main.log', mode='w')      # 'w' mode to overwrite file on each run
    ]
)
logger = logging.getLogger(__name__)

class PipelineHandler():
    def __init__(self, base_url, private_token, user_id=None, project_id=None, branch_name=None, stage_name=None):
        """
        Initialize the PipelineHandler with connection details.
        """
        # Initialize ConnectionManager and establish a connection
        self.connection_manager = ConnectionManager(base_url=base_url, private_token=private_token)
        self.connection = self.connection_manager.connect()
        
        # Initialize attributes
        self.user_id = user_id
        self.project_id = project_id
        self.branch_name = branch_name
        self.stage_name = stage_name
        
        # Set initial placeholders for lazy loading
        self.file_content = None
        self.project_manager = None
        self.project_resource_manager = None
        self.pipeline_controller = None
        self.variables_handler = None
        
    def get_user_info(self):
        """
        Retrieve user information through the connection manager.
        """
        user_name, user_id = self.connection_manager.check_user()
        if user_name:
            logger.info("User information retrieved successfully.")
            return user_name, user_id
        else:
            logger.error("Failed to retrieve user information.")
            return None
            
    def initialize_user_id(self, user_id):
        """
        Initialize user ID and set up the ProjectManager.
        """
        self.user_id = user_id
        self.project_manager = ProjectManager(connection=self.connection, user_id=self.user_id)
        
    def get_projects(self, sub_group_id=None):
        """
        Initialize the ProjectManager with the user ID and retrieve all projects 
        for a specific user and optional subgroup.
        """
        # Ensure that ProjectManager is initialized before calling fetch_all_projects
        logger.info(f"Initialized ProjectManager for user ID {self.user_id}.")
        
        # Fetch all projects
        projects = self.project_manager.fetch_all_projects(sub_group_id=sub_group_id)
        
        if projects:
            logger.info("Fetched all projects successfully.")
            return projects
        
        logger.error("Failed to fetch projects")
        return None
        
    def initialize_project_id(self, project_id):
        """
        Initialize project ID and set up the ProjectResourceManager.
        """
        self.project_id = project_id
        self.project_resource_manager = ProjectResourceManager(connection=self.connection, project_id=project_id)
        
    def get_branches(self):
        """
        Initialize ProjectResourceManager for a specific project and retrieve all branches.
        """
        logger.info(f"Initialized ProjectResourceManager for project ID {self.project_id}.")
        
        branches = self.project_resource_manager.fetch_all_branches()
        
        if branches:
            logger.info(f"Fetched branches for project ID {self.project_id}.")
            return branches
        
        logger.error(f"Failed to fetch branches for project ID {self.project_id}.")
        return None
        
    def initialize_branch_name(self, branch_name):
        """
        Initialize the branch name.
        """
        self.branch_name = branch_name
        
    def get_file_from_repo(self, file_path):
        """
        Retrieve the .gitlab-ci.yml file for a specified branch.
        """
        try:
            gitlab_ci_yml = self.project_resource_manager.fetch_file_from_repo(
                file_path=file_path, 
                branch_name=self.branch_name
            )
            
            if gitlab_ci_yml:
                logger.info(f".gitlab-ci.yml file retrieved successfully for branch '{self.branch_name}'.")
                self.file_content = gitlab_ci_yml
                return gitlab_ci_yml
            else:
                logger.warning(f".gitlab-ci.yml file not found in branch '{self.branch_name}'.")
                return None
        except Exception as e:
            logger.error(f"An error occurred while fetching .gitlab-ci.yml from branch '{self.branch_name}': {e}")
            return None

    def get_job_stages(self):
        """
        Extract stages from the provided .gitlab-ci.yml content.
        """
        stages = self.project_resource_manager.validate_and_get_job_stages(file_content=self.file_content)
        
        if stages:
            logger.info(f"Stages extracted: {stages}")
            return stages
        
        logger.warning(f"No stages found in the .gitlab-ci.yml file.")
        return None
    
    def initialize_stage_name_and_variable_handler(self, stage_name):
        """
        Initialize the stage name and set up the VariablesManager.
        """
        self.stage_name = stage_name
        self.variables_handler = VariablesManager(
            project_id=self.project_id, 
            stage_name=self.stage_name, 
            file_content=self.file_content,
            pipeline_handler=self
        )
    
    def get_all_tags(self):
        """
        Retrieve all tags for the initialized project.
        """
        return self.project_resource_manager.fetch_all_tags()
        
    def get_bgt_db_versions(self, dbname):
        """
        Retrieve database versions for a specific database.
        """
        return self.project_resource_manager.fetch_bgt_db_versions(dbname=dbname, branch_name=self.branch_name)
        
    @StageFunctionRegistry.dynamic_call  
    def get_job_variables(self, *args, **kwargs):
        """
        Retrieve and execute the mapped function if available;
        otherwise, execute default logic.
        """
        # Use dynamic_call to get the mapped function
        variables = self.variables_handler.get_variables_from_yml()
        if variables:
            return variables
        
        return None
        
    def initialize_pipeline_controller(self):
        """
        Initialize the PipelineController to manage pipeline operations.
        """
        self.pipeline_controller = PipelineController(
            connection=self.connection,
            project_id=self.project_id,
            branch_name=self.branch_name
        )
        
    def trigger_job(self, variables):
        """
        Trigger a pipeline job with specified variables.
        """
        return self.pipeline_controller.trigger_pipeline_job(variables=variables)
    
    def monitor_jobs(self, pipeline_id, interval):
        """
        Monitor the status of jobs in a pipeline.
        """
        return self.pipeline_controller.monitor_pipeline_jobs(pipeline_id=pipeline_id, interval=interval)
    
    def download_artifact(self, job_id, artifact_name, directory):
        """
        Download artifacts from a specified job.
        """
        return self.pipeline_controller.download_artifacts(
            job_id=job_id, 
            artifact_name=artifact_name,
            directory=directory
        )
     
    def show_options(self, selection_list, txt, display_horizontal=False):
        """
        Display options to the user and prompt for a selection. Supports horizontal or vertical display.
        """
        console = Console()
        
        try:
            if not selection_list:
                logger.error("The selection list is empty.")
                print("No options available to select.")
                return None

            logger.info(f"Displaying {len(selection_list)} options to the user.")
            console.print(f"[bold magenta]Please select a {txt} from the list below:[/bold magenta]")

            # Determine if the list contains dictionaries or simple items
            is_dict = isinstance(selection_list[0], dict)
            options = []
            color = "cyan"
            for idx, option in enumerate(selection_list, 1):
                if is_dict:
                    options.append(f"{idx}. [{color}]{option['name'].upper()}[/{color}]")
                else:
                    options.append(f"{idx}. [{color}]{str(option).upper()}[/{color}]")

            #Add Back To Projects option to the list
            options.append(f"{len(selection_list) + 1}. [bold red]BACK[/bold red]")
            
            # Add EXIT option to the list
            options.append(f"{len(selection_list) + 2}. [bold red]EXIT[/bold red]")

            # Display options based on `display_horizontal` flag
            if display_horizontal:
                console.print(" | ".join(options))
            else:
                for option in options:
                    console.print(option)

            # Prompt user input
            console.print("[bold blue]Enter the number of your choice: [/bold blue]", end="")
            choice = int(input())
            logger.info(f"User input for choice: {choice}")

            # Handle user choice
            if choice == len(selection_list) + 2:
                console.print("[red]Exiting the program.[/red]")
                sys.exit(0)
            
            if choice == len(selection_list) + 1:
                return 'menu'

            if 1 <= choice <= len(selection_list):
                selected_option = selection_list[choice - 1]
                if is_dict:
                    logger.info(f"User selected: {selected_option['name']}")
                    console.print(f"[bold green]You selected: {selected_option['name'].upper()}[/bold green]")
                else:
                    logger.info(f"User selected: {selected_option}")
                    console.print(f"[bold green]You selected: {str(selected_option).upper()}[/bold green]")
                return selected_option
            else:
                logger.warning(f"Invalid selection: {choice}. Out of bounds.")
                console.print("[red]Invalid selection. Please choose a valid option.[/red]")
                return self.show_options(selection_list, txt, display_horizontal)

        except ValueError:
            logger.error("Invalid input. A number was expected.")
            console.print("[red]Please enter a valid number.[/red]")
            return self.show_options(selection_list, txt, display_horizontal)

        except Exception as e:
            logger.exception("An unexpected error occurred.")
            console.print("[red]An error occurred. Please try again.[/red]")
            sys.exit(1)       