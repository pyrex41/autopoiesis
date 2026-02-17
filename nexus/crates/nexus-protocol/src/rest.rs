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

    pub async fn list_snapshots(&self) -> Result<Vec<SnapshotData>, ProtocolError> {
        let resp = self
            .build_request(reqwest::Method::GET, "/api/snapshots")
            .send()
            .await?
            .error_for_status()?
            .json::<Vec<SnapshotData>>()
            .await?;
        Ok(resp)
    }

    pub async fn get_snapshot(&self, id: &str) -> Result<SnapshotData, ProtocolError> {
        let path = format!("/api/snapshots/{}", id);
        let resp = self
            .build_request(reqwest::Method::GET, &path)
            .send()
            .await?
            .error_for_status()?
            .json::<SnapshotData>()
            .await?;
        Ok(resp)
    }

    pub async fn list_branches(&self) -> Result<(Vec<BranchData>, Option<String>), ProtocolError> {
        #[derive(serde::Deserialize)]
        struct BranchesResponse {
            branches: Vec<BranchData>,
            #[serde(default)]
            current: Option<String>,
        }
        let resp = self
            .build_request(reqwest::Method::GET, "/api/branches")
            .send()
            .await?
            .error_for_status()?
            .json::<BranchesResponse>()
            .await?;
        Ok((resp.branches, resp.current))
    }

    pub async fn get_snapshot_diff(
        &self,
        from_id: &str,
        to_id: &str,
    ) -> Result<String, ProtocolError> {
        let path = format!("/api/snapshots/{}/diff/{}", from_id, to_id);
        let text = self
            .build_request(reqwest::Method::GET, &path)
            .send()
            .await?
            .error_for_status()?
            .text()
            .await?;
        Ok(text)
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

    #[test]
    fn test_rest_client_build_request_url() {
        let client = RestClient::new("http://localhost:8080", None);
        let req = client.build_request(reqwest::Method::GET, "/api/snapshots");
        let built = req.build().unwrap();
        assert_eq!(built.url().as_str(), "http://localhost:8080/api/snapshots");
    }

    #[test]
    fn test_rest_client_build_request_with_auth() {
        let client = RestClient::new("http://localhost:8080", Some("tok".to_string()));
        let req = client.build_request(reqwest::Method::GET, "/api/branches");
        let built = req.build().unwrap();
        let auth = built.headers().get("authorization").unwrap().to_str().unwrap();
        assert!(auth.starts_with("Bearer "));
    }

    #[test]
    fn test_rest_client_snapshot_diff_path() {
        let client = RestClient::new("http://localhost:8080", None);
        let req = client.build_request(
            reqwest::Method::GET,
            &format!("/api/snapshots/{}/diff/{}", "abc", "def"),
        );
        let built = req.build().unwrap();
        assert_eq!(
            built.url().as_str(),
            "http://localhost:8080/api/snapshots/abc/diff/def"
        );
    }
}
