import Foundation

enum WebReaderError: Error {
    case invalidURL(String)
    case insecureURL(URL)
    case navigationFailed(URLError.Code)
    case timeout(TimeInterval)
    case emptyContent(URL)
    case extractionFailed(URL)

    static func validate(urlString: String) -> Result<URL, WebReaderError> {
        guard let url = URL(string: urlString),
              url.host != nil else {
            return .failure(.invalidURL(urlString))
        }

        guard url.scheme == "https" else {
            return .failure(.insecureURL(url))
        }

        return .success(url)
    }
}
