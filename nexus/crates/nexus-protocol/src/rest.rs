use reqwest::Client;
use uuid::Uuid;

use crate::error::ProtocolError;
use crate::types::*;

pub struct RestClient {
    client: Client,
    base_url: String,
    api_key: Option<String>,
}

impl RestClient {
    pub fn new(base_url: &str, api_key: Option<String>) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.trim_end_matches('/').to_string(),
            api_key,
        }
    }

    fn build_request(&self, method: reqwest::Method, path: &str) -> reqwest::RequestBuilder {
        let url = format!("{}{}", self.base_url, path);
        let mut req = self.client.request(method, &url);
        if let Some(ref key) = self.api_key {
            req = req.bearer_auth(key);
        }
        req
    }

    pub async fn system_info(&self) -> Result<SystemInfoData, ProtocolError> {
        let resp = self
            .build_request(reqwest::Method::GET, "/api/system-info")
            .send()
            .await?
            .error_for_status()?
            .json::<SystemInfoData>()
            .await?;
        Ok(resp)
    }

    pub async fn list_agents(&self) -> Result<Vec<AgentData>, ProtocolError> {
        let resp = self
            .build_request(reqwest::Method::GET, "/api/agents")
            .send()
            .await?
            .error_for_status()?
            .json::<Vec<AgentData>>()
            .await?;
        Ok(resp)
    }

    pub async fn get_agent(&self, id: Uuid) -> Result<AgentData, ProtocolError> {
        let path = format!("/api/agents/{}", id);
        let resp = self
            .build_request(reqwest::Method::GET, &path)
            .send()
            .await?
            .error_for_status()?
            .json::<AgentData>()
            .await?;
        Ok(resp)
    }

    pub async fn create_agent(
        &self,
        name: &str,
        capabilities: Vec<String>,
    ) -> Result<AgentData, ProtocolError> {
        let body = serde_json::json!({
            "name": name,
            "capabilities": capabilities,
        });
        let resp = self
            .build_request(reqwest::Method::POST, "/api/agents")
            .json(&body)
            .send()
            .await?
            .error_for_status()?
            .json::<AgentData>()
            .await?;
        Ok(resp)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rest_client_construction() {
        let client = RestClient::new("http://localhost:8080", None);
        assert_eq!(client.base_url, "http://localhost:8080");
        assert!(client.api_key.is_none());
    }

    #[test]
    fn test_rest_client_trailing_slash() {
        let client = RestClient::new("http://localhost:8080/", None);
        assert_eq!(client.base_url, "http://localhost:8080");
    }

    #[test]
    fn test_rest_client_with_api_key() {
        let client = RestClient::new("http://localhost:8080", Some("secret".to_string()));
        assert_eq!(client.api_key, Some("secret".to_string()));
    }
}
