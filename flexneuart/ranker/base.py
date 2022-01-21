#
#  Copyright 2014+ Carnegie Mellon University
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

"""
 FlexNeuART base class for ranking model wrappers.
"""
from flexneuart.retrieval.utils import query_dict_to_dataentry_fields, DataEntryFields


class BaseRanker:
    """A base re-ranker class."""
    def get_query_info_obj(self, query_info_obj_or_dict):
        """an instance of
                i) a DataEntryFields object
                ii) a dictionary object, which will the function
                    try to convert to DataEntryFields

        :param query_info_obj_or_dict: a DataEntryFields object
        :return:
        """
        if type(query_info_obj_or_dict) == dict:
            query_info_obj = query_dict_to_dataentry_fields(query_info_obj_or_dict)
        else:
            if type(query_info_obj_or_dict) != DataEntryFields:
                raise Exception('A query object info type should be DataEntryFields or a dictionary!')
            query_info_obj = query_info_obj_or_dict
        return query_info_obj

    def rank_candidates(self, cand_list, query_info_obj_or_dict):
        """Score and rank a list of candidates obtained from the candidate provider.
           Note that this function may (though this is ranker-dependent) use all query field fields,
           not just a field that was used to retrieve the list of candidate entries!

        :param cand_list:           a list of the objects of the type CandidateEntry
        :param query_info_obj:      an instance of
                                        i) a DataEntryFields object
                                        ii) a dictionary object, which will the function
                                            try to convert to DataEntryFields

        :return a list of tuples (document id, score) sorted in the order of decreasing scores
        """
        tmp_res = []

        for did, score in self.score_candidates(cand_list, query_info_obj_or_dict).items():
            tmp_res.append( (score, did))

        tmp_res.sort(reverse=True)

        return [ (did, score) for score, did in tmp_res]

    def score_candidates(self, cand_list, query_info_obj_or_dict):
        """Score, but does not rank, a candidate list obtained from the candidate provider.
           Note that this function may (though this is ranker-dependent) use all query field fields,
           not just a field that was used to retrieve the list of candidate entries!

        :param cand_list:           a list of the objects of the type CandidateEntry
        :param query_info_obj:      an instance of
                                        i) a DataEntryFields object
                                        ii) a dictionary object, which will the function
                                            try to convert to DataEntryFields

        :return:  a dictionary where keys are document IDs and values are document scores
        """
        raise NotImplementedError

