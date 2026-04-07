import Foundation
import Testing
@testable import Conductor

@Suite("PubMed Tests")
struct PubMedTests {

    // MARK: - JSON Decoding

    @Test("Decodes esearch JSON response for PMIDs")
    func decodesESearchResponse() throws {
        let json = """
        {
            "esearchresult": {
                "idlist": ["38000000", "37999999", "37999998"]
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PubMedSearchResponse.self, from: data)
        #expect(response.esearchresult.idlist == ["38000000", "37999999", "37999998"])
    }

    @Test("Decodes esearch JSON with empty idlist")
    func decodesEmptyIDList() throws {
        let json = """
        {
            "esearchresult": {
                "idlist": []
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PubMedSearchResponse.self, from: data)
        #expect(response.esearchresult.idlist.isEmpty)
    }

    // MARK: - XML Parsing

    @Test("Parses efetch XML into articles with authors, title, abstract, PMID")
    func parsesFullArticle() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <PubmedArticleSet>
          <PubmedArticle>
            <MedlineCitation>
              <PMID Version="1">12345678</PMID>
              <Article>
                <ArticleTitle>CRISPR-Cas9 genome editing in human cells</ArticleTitle>
                <Abstract>
                  <AbstractText>We demonstrate efficient editing of the human genome using CRISPR-Cas9 technology in cultured human cells.</AbstractText>
                </Abstract>
                <AuthorList>
                  <Author>
                    <LastName>Zhang</LastName>
                    <ForeName>Feng</ForeName>
                  </Author>
                  <Author>
                    <LastName>Doudna</LastName>
                    <ForeName>Jennifer A</ForeName>
                  </Author>
                </AuthorList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
        </PubmedArticleSet>
        """
        let data = Data(xml.utf8)
        let articles = PubMedXMLParser.parse(data: data)

        #expect(articles.count == 1)

        let article = articles[0]
        #expect(article.pmid == "12345678")
        #expect(article.title == "CRISPR-Cas9 genome editing in human cells")
        #expect(article.abstract.contains("CRISPR-Cas9"))
        #expect(article.authors.count == 2)

        let firstAuthor = article.authors[0]
        #expect(firstAuthor.lastName == "Zhang")
        #expect(firstAuthor.foreName == "Feng")

        let secondAuthor = article.authors[1]
        #expect(secondAuthor.lastName == "Doudna")
        #expect(secondAuthor.foreName == "Jennifer A")
    }

    @Test("Parses multiple articles from XML")
    func parsesMultipleArticles() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <PubmedArticleSet>
          <PubmedArticle>
            <MedlineCitation>
              <PMID Version="1">11111111</PMID>
              <Article>
                <ArticleTitle>Article One</ArticleTitle>
                <Abstract>
                  <AbstractText>Abstract for article one.</AbstractText>
                </Abstract>
                <AuthorList>
                  <Author>
                    <LastName>Smith</LastName>
                    <ForeName>John</ForeName>
                  </Author>
                </AuthorList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
          <PubmedArticle>
            <MedlineCitation>
              <PMID Version="1">22222222</PMID>
              <Article>
                <ArticleTitle>Article Two</ArticleTitle>
                <Abstract>
                  <AbstractText>Abstract for article two.</AbstractText>
                </Abstract>
                <AuthorList>
                  <Author>
                    <LastName>Jones</LastName>
                    <ForeName>Mary</ForeName>
                  </Author>
                </AuthorList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
        </PubmedArticleSet>
        """
        let data = Data(xml.utf8)
        let articles = PubMedXMLParser.parse(data: data)

        #expect(articles.count == 2)
        #expect(articles[0].pmid == "11111111")
        #expect(articles[0].title == "Article One")
        #expect(articles[1].pmid == "22222222")
        #expect(articles[1].title == "Article Two")
    }

    @Test("Returns empty abstract for article with no abstract element")
    func handlesArticleWithNoAbstract() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <PubmedArticleSet>
          <PubmedArticle>
            <MedlineCitation>
              <PMID Version="1">99999999</PMID>
              <Article>
                <ArticleTitle>A Study Without Abstract</ArticleTitle>
                <AuthorList>
                  <Author>
                    <LastName>Brown</LastName>
                    <ForeName>Alice</ForeName>
                  </Author>
                </AuthorList>
              </Article>
            </MedlineCitation>
          </PubmedArticle>
        </PubmedArticleSet>
        """
        let data = Data(xml.utf8)
        let articles = PubMedXMLParser.parse(data: data)

        #expect(articles.count == 1)
        #expect(articles[0].abstract == "")
    }
}
