import requests

response = requests.get('http://localhost:8000/')
print(f"Status: {response.status_code}")
print(f"Response: {response.json()}")
