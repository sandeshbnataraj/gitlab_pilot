import logging
import yaml
import re
import sys
from rich.console import Console

class VariablesManager:
    
    console = Console()
    
    def __init__(self, project_id, stage_name, file_content, pipeline_handler):
        self.project_id = project_id
        self.stage_name = stage_name
        self.file_content = file_content
        self.pipeline_handler = pipeline_handler
    
    # Default method to retrieve variables from YAML content
    def get_variables_from_yml(self):
        """
        Extract variables from the provided .gitlab-ci.yml content.
        """
        try:
            yml_data = yaml.safe_load(self.file_content)
            variables = {}

            # Extract global variables
            if 'variables' in yml_data:
                global_vars = {k: v for k, v in yml_data['variables'].items() if k.startswith('INO_')}
                variables.update(global_vars)

            # Check for stage-specific variables    
            if self.stage_name in yml_data and 'variables' in yml_data[self.stage_name]:
                stage_vars = {k: v for k, v in yml_data[self.stage_name]['variables'].items() if k.startswith('INO_')}
                variables.update(stage_vars)

            return list(variables.keys()) if variables else None

        except yaml.YAMLError as e:
            logging.error(f"Failed to extract variables from YAML file: {e}")
            return None
    
    def bgt_db_create_release(self, *args, **kwargs):
        """
        Function registered for 'create_db_release' stage in project 84.
        Prompts user for values of required variables, with additional handling for 'INO_TAG_NAME'.
        """
        variables = self.get_variables_from_yml()
        var_dict = {'TRIGGER_TARGET': self.stage_name}
        
        if variables:
            logging.info(f"The job '{self.stage_name}' requires the following variables:")
            print(f"The job '{self.stage_name}' accepts the following variables:")
            
            for var_name in variables:           
                # Special handling for 'INO_TAG_NAME'
                if var_name == 'INO_TAG_NAME':
                    # Get tags from the project
                    tags = self.pipeline_handler.get_all_tags()
                    
                    tags.append({
                        'name': 'current_release',
                        'message': 'to get current db release'
                    })
                    
                    # Show options for the user to select a tag
                    selected_tag = self.pipeline_handler.show_options(
                        selection_list=tags, 
                        txt='tag', 
                        display_horizontal=False
                    )
                    
                    if not selected_tag:
                        print("Invalid selection. Exiting.")
                        sys.exit(0)
            
                    if selected_tag == 'menu':
                        print("Returning to variable selection")
                        self.bgt_db_create_release(*args, **kwargs)
                    
                    # Handle 'current_release' selection case  
                    var_dict[var_name] = "" if selected_tag['name'].lower() == 'current_release' else selected_tag['name'] 
                else:  
                    # Prompt user for other variable values 
                    var_value = input(f"Enter the value for {var_name}(optional): ").strip()
                    if var_value:  # Only add if input is provided
                        var_dict[var_name] = var_value
                
        return var_dict
    
    def bgt_db_update_version(self, *args, **kwargs):
        """
        Function registered for 'update_version' stage in project 84.
        Handles database and version-specific variable retrieval.
        """
        variables = self.get_variables_from_yml()
        var_dict = {'TRIGGER_TARGET': self.stage_name}
        
        if variables:
            for var_name in variables:
                if var_name == 'INO_DBNAME':
                    db_name_list = ['AGT', 'AWB', 'ALL']
                    selectd_db = self.pipeline_handler.show_options(
                        selection_list=db_name_list,   
                        txt='database',
                        display_horizontal=True
                    ).lower()
                    
                    if not selectd_db:
                        print("Invalid selection. Exiting.")
                        sys.exit(0)
            
                    if selectd_db == 'menu':
                        print("Returning to variable selection")
                        self.bgt_db_update_version(*args, **kwargs)
                    
                    if selectd_db == 'all':
                        var_dict[var_name] = "datatrak_bgt_agt,datatrak_bgt_awb"
                    else:
                        var_dict[var_name] = f"datatrak_bgt_{selectd_db}"
                        
                if var_name in ['INO_NEWVERSION','INO_OLDVERSION']:
                    current_version_key = "new_version" if var_name == 'INO_NEWVERSION' else "old_version"
                    
                    # Handle multiple databases if selected    
                    db_names = var_dict['INO_DBNAME'].split(',') if isinstance(var_dict['INO_DBNAME'], str) else var_dict['INO_DBNAME']
                        
                    for dbname in db_names:
                        curr_version_info = self.pipeline_handler.get_bgt_db_versions(
                            dbname=dbname
                        )
                        
                        current_version = curr_version_info[current_version_key]
                        logging.info(f"Current version for db {dbname}: {current_version_key}={current_version}")
                        print(f"Current version for db {dbname}: {current_version_key}={current_version}")
                        
                        # Ask if they want to enter the full version or just the build number
                        choice = input("Do you want to enter the (1) full version or (2) build number only? Enter 1 or 2: ").strip()
                        
                        if choice == '1':
                            full_version = input("Enter the full version (e.g.,v1.2.1-b12): ").strip()
                            
                            pattern = r"^v\d+\.\d+\.\d+-b\d+[a-zA-Z0-9_]*$"
                            
                            if re.match(pattern=pattern, string=full_version):
                                print("Version Updated!")
                                var_dict[var_name] = full_version
                            else:
                                print("Version did not match the pattern (Example formats: v1.2.0-b21, v1.2.0-b24_ama_butn)")
                                sys.exit(0)
                                
                        elif choice == '2':
                            build_number = input("Enter the build number (e.g.,12 or 24_AMA_BTN): ").strip()
                            
                            pattern = r"^\d+[a-zA-Z0-9_]*$"
                            
                            if re.match(pattern=pattern, string=build_number):
                                base_version, curr_build = current_version.split('-b',1)
                                full_version = f"{base_version}-b{build_number}"
                                logging.info(f"Constructed version: {full_version}")
                                var_dict[var_name] = full_version
                        else:
                            print("Invalid selection sxiting")
                            sys.exit(0)
                            
        return var_dict
    
    # Project Id 84 (snataraj/dbs-bgt)
    def get_var_84_create_db_release(self, *args, **kwargs):
        return self.bgt_db_create_release(*args, **kwargs)                    

    def get_var_84_update_version(self, *args, **kwargs):
        return self.bgt_db_update_version(*args, **kwargs)
    
    # Project Id 73 (ilts/datatrak-flx/bgt/dta/dbs) 
    def get_var_73_create_db_release(self, *args, **kwargs):
        return self.bgt_db_create_release(*args, **kwargs)   

    def get_var_73_update_version(self, *args, **kwargs):
        return self.bgt_db_update_version(*args, **kwargs)