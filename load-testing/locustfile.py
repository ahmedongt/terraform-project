from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    # Simulates a user waiting 1 to 3 seconds between actions
    wait_time = between(1, 3)

    @task(3)
    def load_homepage(self):
        # Sends a GET request to your application's frontend/ALB
        self.client.get("/")

    @task(1)
    def simulate_health_check(self):
        # Simulates a lightweight secondary request
        self.client.get("/", headers={"User-Agent": "Locust-Load-Test"})