import logging

class ProjectManager:
    def __init__(self, connection, user_id):
        self.connection = connection
        self.user_id = user_id
    
    def categorize_project(self, project):
        """
        Categorize a project based on ownership and type into predefined categories.
        """
        # Check if the project is owned by the authenticated user
        if hasattr(project, 'owner') and project.owner['id'] == self.user_id:
            logging.info(f"Project '{project.name}' categorized as 'owned'")
            return 'owned'
        
        # Check if it's a personal project owned by a teammate
        if project.namespace['kind'] == 'user' and project.owner['id'] != self.user_id:
            logging.info(f"Project '{project.name}' categorized as 'teammate_projects'")
            return 'teammate_projects'

        # Check if it's a group project (namespace.kind == 'group')
        if project.namespace['kind'] == 'group':
            # Categorize group projects based on their path
            project_path = project.path_with_namespace
            for category in ['bgt','stm','pgmc']:
                if category in project_path:
                    logging.info(f"Project '{project.name}' categorized as '{category}'")
                    return category
                    
        # Default category for all other projects
        logging.info(f"Project '{project.name}' categorized as 'allothers'")
        return 'others'
    
    def fetch_all_projects(self, sub_group_id=None):
        """
        Fetch all projects within a GitLab subgroup, including subgroups, and categorize them.
        """
        # Initialize the project categories
        all_projects = {
            'owned': [],  # Projects owned by the user
            'teammate_projects': [],  # Teammates' personal projects
            'bgt': [],  # Group projects categorized as 'bgt'
            'stm': [],  # Group projects categorized as 'stm'
            'pgmc': [],  # Group projects categorized as 'pgmc'
            'others': []  # Other group projects not falling into the above categories
        } 
        
        if sub_group_id:
            logging.info(f"Starting project retrieval for subgroup ID: {sub_group_id}")
            projects = self.connection.groups.get(sub_group_id).projects.list(all=True, include_subgroups=True)
        else:
            logging.info("Fetching all projects the user has access to.")
            projects = self.connection.projects.list(membership=True, all=True)
            
        
        for project in projects:
            category = self.categorize_project(project=project)
            all_projects[category].append({
                'id': project.id,
                'name': project.name
            })
        
        logging.info("Project retrieval and categorization completed successfully.")
        return all_projects