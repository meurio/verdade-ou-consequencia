class User < ActiveRecord::Base
  has_many :questions
  has_many :authorizations
  has_many :answers, :as => :responder

  belongs_to :candidate
  belongs_to :city
  
  validates_presence_of :email, :name, :city_id

  before_save :corrige_dados
  before_create :corrige_dados

  attr_accessible :candidate_id, :email, :name, :picture, :mobile_phone, :city_id

  def self.create_from_hash!(hash)
    user = User.new
    if hash['info']['email']
      user.email = hash['info']['email']
      user.email_validated = true
    else
      user.email = ''
      user.email_validated = false
    end
    user.name = "#{hash['info']['name']}"
    user.picture =hash['info']['image_url'] || hash['info']['image']
    user.save(:validate => false)
    user
  end

  def percent_care(qtde)
    qtde * 100 / answers.select{|a| a.weight > 0}.count
  end


  def matches
    match_data = Candidate.
      select(
        %Q{
          (
            select
                count(*)
              from 
                answers ca 
                inner join
                  answers ua
                  on (ua.responder_id = #{id}) and (ca.question_id = ua.question_id) and (ua.responder_type = 'User') and (ua.weight>0)
              where 
                ca.responder_id = candidates.id and ca.responder_type='Candidate' and ca.short_answer = 'Sim'
          ) as score
          , candidates.nickname
          , candidates.id as id
          , (select u.score from parties_unions pu inner join unions u on pu.union_id = u.id where pu.party_id = candidates.party_id and u.city_id = candidates.city_id) as union_score
          , parties.score as party_score
          , (select count(*) from users us where us.candidate_id = candidates.id) as votos 
        }).
      joins(:party).
      where("candidates.finished_at is not null and candidates.city_id = #{city_id}")

    match_data.each do |dt| 
      dt['score'] = dt['score'].to_i
      dt['union_score'] = dt['union_score'].to_f if dt['union_score']
      dt['party_score'] = dt['party_score'].to_f
      dt['score_final'] = dt['score'] * (dt['union_score'] ? dt['union_score'] : dt['party_score'])
      dt['votos'] = dt['votos'].to_i
    end

    x = match_data.select{ |dt| dt.score > 0 }

    if (x.count == 0) # Se não houver ninguém, mostra o que tem
      x = match_data
    end
    x.map do |dt|
      {
        :score => dt.score,
        :union_score => dt.union_score,
        :party_score => dt.party_score,
        :score_final => dt.score_final,
        :id => dt.id,
        :nickname => dt.nickname,
        :votos => dt.votos
      }
    end.sort { |a,b| 
      (a[:score_final] != b[:score_final]) ? (a[:score_final] - b[:score_final]) :
      (a[:union_score] != b[:union_score]) ? (a[:union_score] - b[:union_score]) :
      (a[:party_score] != b[:party_score]) ? (a[:party_score] - b[:party_score]) :
      (a[:score] != b[:score]) ? (a[:score] - b[:score]) :
      (a[:votos] != b[:votos]) ? (a[:votos] - b[:votos]) : a[:nickname] <=> b[:nickname]
    }.reverse
  end

  private

  def corrige_dados
    self.mobile_phone.gsub! /\D/, '' if self.mobile_phone  != nil
  end
end
