import logging
import base64
import gitlab
import yaml
import re

class ProjectResourceManager():
    def __init__(self, connection, project_id):
        """
        Initialize the GitLab connection.
        """
        self.connection = connection
        self.project_id = project_id
    
    def fetch_all_branches(self):
        """
        Retrieve all branches in a GitLab project.
        """
        try:
            # Fetch all branches
            branches = self.connection.projects.get(self.project_id).branches.list(all=True)
            branch_names = [branch.name for branch in branches]
            
            logging.info(f"Retrieved branches for project ID {self.project_id}: {branch_names}")
            return branch_names
        
        except gitlab.exceptions.GitlabGetError as e:
            logging.error(f"Failed to retrieve branches for project ID {self.project_id}: {e}")
            return None 
        
    def fetch_file_from_repo(self, file_path, branch_name):
        """
        Retrieve the .gitlab-ci.yml file content from a specific branch in the project.
        """
        file = self.connection.projects.get(self.project_id).files.get(file_path=file_path, ref=branch_name)

        file_content = base64.b64decode(file.content).decode('utf-8')
            
        logging.info(f"Successfully retrieved .gitlab-ci.yml file from project ID {self.project_id} on branch '{branch_name}'.")
        return file_content
    
    def validate_and_get_job_stages(self, file_content):
        """
        Extract stages from the provided .gitlab-ci.yml content.
        """
        try:
            yml_data = yaml.safe_load(file_content)
            stages = yml_data.get('stages',None)
            
            if stages:
                logging.info(f"Stages extracted: {stages}")
                return stages
            else:
                logging.warning(f"No stages found in the .gitlab-ci.yml file.")
                return None

        except yaml.YAMLError as e:
            logging.error(f"Failed to parse .gitlab-ci.yml file: {e}")
            return None
        
    def fetch_all_tags(self):
        """
        Retrieve all tags for a specified project.
        """
        try:
            tags = self.connection.projects.get(self.project_id).tags.list(all=True)
            
            if tags:
                all_tags = [{'name': tag.name, 'message': tag.message} for tag in tags]
                logging.info(f"Found tags: {all_tags}")
                return all_tags

            logging.info("No tags found.")
            return None
        
        except Exception as e:
            logging.error(f"Error fetching tags: {e}")
            return None
        
    def fetch_bgt_db_versions(self, dbname, branch_name):
        """
        Retrieve the version information from the version.txt file within a specified branch and database.
        """
        logging.info(f"Retrieving version information from {dbname}/version.txt for project ID: {self.project_id}.")
        response = self.fetch_file_from_repo(file_path=f"{dbname}/version.txt", branch_name=branch_name)
        print(response)
        version_info = {}
        
        if response:
            for line in response.splitlines():
                if "=" in line:
                    key, value = line.split('=',1)
                    
                    key_pattern = r"^(new_version|old_version)$"
                    value_pattern = r"^v\d+\.\d+\.\d+-b\d+(_[a-zA-Z0-9_]+)?$"
                    
                    if re.match(pattern=key_pattern, string=key) and re.match(pattern=value_pattern, string=value):
                        version_info[key.strip()] = value.strip()
                    else:
                        logging.error("Failed to retrieve version information.")
                        return None

        if version_info:
            logging.info(f"Version information retrieved: {version_info}")
            return version_info

        logging.error("Failed to retrieve version information.")
        return None