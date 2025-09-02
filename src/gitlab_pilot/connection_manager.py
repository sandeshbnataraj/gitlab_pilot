import gitlab
import logging
from gitlab.exceptions import GitlabAuthenticationError, GitlabConnectionError

class ConnectionManager:
    def __init__(self, base_url, private_token):
        self.base_url = base_url
        self.private_token = private_token
        self.connection = None  # Connection will be established lazily
        
    def connect(self):
        """Establish and authenticate the connection to GitLab."""
        if not self.connection: # Only connect if no active connection exists
            try:
                self.connection = gitlab.Gitlab(self.base_url, private_token=self.private_token)
                self.connection.auth() # Authenticate the connection

                logging.info("Connected to GitLab successfully!")
                return self.connection
            except GitlabAuthenticationError:
                logging.error("Authentication failed. Please check your access token.")
                self.connection = None
            except GitlabConnectionError:
                logging.error("Failed to connect to GitLab. Please check the URL and network connection.")
                self.connection = None
            except Exception as e:
                logging.error(f"An unexpected error occurred: {e}")
                self.connection = None
                
    def check_user(self):
        """Verify if the user is authenticated. Returns the username if successful."""
        if not self.connection:
            self.connect()
            
        try:
            user = self.connection.user
            logging.info(f"Authenticated as: {user.name}")
            return (user.name, user.id)
        except GitlabAuthenticationError:
            logging.error("User authentication failed.")
            return None
        except Exception as e:
            logging.error(f"An error occurred while fetching user details: {e}")
            return None
        
    def get(self, endpoint):
        """Send a GET request to a specified GitLab endpoint."""
        if not self.connection:
            self.connect()
            
        try:
            response = self.connection.http_get(endpoint)
            return response
        except GitlabConnectionError:
            logging.error("Failed to connect to the endpoint.")
            return None
        except Exception as e:
            logging.error(f"An error occurred during GET request: {e}")
            return None
        
    def post(self, endpoint, data, timeout=30):
        """Send a POST request with data to a specified GitLab endpoint."""
        if not self.connection:
            self.connect()
            
        try:
            response = self.connection.http_post(endpoint, data=data, timeout=timeout)
            return response
        except GitlabConnectionError:
            print("Failed to connect to the endpoint.")
            return None
        except Exception as e:
            print(f"An error occurred during POST request: {e}")
            return None
        
    def reconnect(self):
        """Reinitialize the connection to GitLab."""
        self.connection = None
        return self.connect()