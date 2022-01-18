
import Combine
import Foundation

struct GitHubCommitAuthorInfo: Decodable {
    let name: String
    let email: String
    let date: String
}

struct GitHubCommitInfo: Decodable {
    let author: GitHubCommitAuthorInfo
    let committer: GitHubCommitAuthorInfo
    let message: String
}

struct GitHubCommit: Decodable {
    let sha: String
    let commit: GitHubCommitInfo
}

struct GitHub {
    static func getLatestCommitForFile(
        author: String,
        repository: String,
        filePath: String,
        completion: @escaping (GitHubCommit) -> Void
    ) -> AnyCancellable {
        let url = URL(string: "https://api.github.com/repos/\(author)/\(repository)/commits?path=\(filePath)&page=1&per_page=1")!
        return URLSession.shared.get(url, defaultValue: []) { (commits: [GitHubCommit]) in
            completion(commits[0])
        }
    }

    static func getFile(
        author: String,
        repository: String,
        filePath: String,
        completion: @escaping (String) -> Void
    ) -> AnyCancellable {
        let url = URL(string: "https://github.com/\(author)/\(repository)/raw/master/\(filePath)")!
        return URLSession.shared.get(url, defaultValue: "", completion: completion)
    }
    
    static func downloadFile(
        author: String,
        repository: String,
        filePath: String,
        completion: @escaping (URL) -> Void
    ) -> AnyCancellable {
        let url = URL(string: "https://github.com/\(author)/\(repository)/raw/master/\(filePath)")!
        return URLSession.shared.download(url, defaultValue: URL(fileURLWithPath: ""), completion: completion)
    }
}
